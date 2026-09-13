//! The actor thread of §2.3.
//!
//! `AppState` lives on **one** dedicated thread and is reached through a command
//! channel. Nothing else may hold a reference to it, which is what makes every
//! mutation serialised and removes a whole class of lock-ordering bugs before it
//! can exist. Callers hand over a closure and block on a reply channel; the
//! closure runs on the actor thread, with `&mut AppState`, and nothing else runs
//! at the same time.
//!
//! Two deliberate absences:
//!
//! * **No async runtime.** The channel is `std::sync::mpsc`. The core has no I/O
//!   concurrency to speak of, and §2.6 has no entry for one.
//! * **No timer.** The thread blocks on `recv` and wakes only when a command
//!   arrives, so an idle window costs nothing — the 0% idle CPU budget of §1.3
//!   is met by construction rather than by tuning.
//!
//! Long jobs — pagination, PDF export, the library scan — do **not** belong
//! here. §2.3 puts them on a worker pool against an immutable snapshot, and they
//! arrive with the phase that needs them.

use std::sync::mpsc::{self, Sender};
use std::sync::OnceLock;

use crate::state::AppState;

/// A unit of work for the actor thread.
type Job = Box<dyn FnOnce(&mut AppState) + Send>;

pub struct Actor {
    jobs: Sender<Job>,
}

impl Actor {
    fn spawn() -> Actor {
        let (jobs, inbox) = mpsc::channel::<Job>();
        std::thread::Builder::new()
            .name("slugline-core".to_owned())
            .spawn(move || {
                let mut state = AppState::default();
                // Ends when the last sender drops, which only happens at
                // process exit: the channel lives in a `static`.
                for job in inbox {
                    // A panicking command must not take the whole core down
                    // with it: without this, one bad closure kills the thread
                    // and every later `run` blocks on `recv` forever. The
                    // panicking caller still sees its `recv` fail (its reply
                    // sender is dropped during unwinding), but the actor lives
                    // on for the next command.
                    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        job(&mut state);
                    }));
                }
            })
            .expect("the core actor thread must start");
        Actor { jobs }
    }

    /// Runs `job` on the actor thread and waits for its answer.
    ///
    /// The wait is the point: the caller is an FRB `sync` function on the Dart
    /// thread, and the round trip is two channel sends. §2.3 requires anything
    /// that can exceed 2 ms to be `async` instead, so only the short commands —
    /// read a block, apply an edit — come through here.
    pub fn run<T: Send + 'static>(
        &self,
        job: impl FnOnce(&mut AppState) -> T + Send + 'static,
    ) -> T {
        let (reply, answer) = mpsc::sync_channel::<T>(1);
        self.jobs
            .send(Box::new(move |state| {
                // A closed reply channel means the caller gave up; that is not
                // an error here, and the state change has already happened.
                let _ = reply.send(job(state));
            }))
            .expect("the core actor thread is running");
        answer.recv().expect("the core actor thread answered")
    }
}

/// The one actor, started on first use.
pub fn actor() -> &'static Actor {
    static ACTOR: OnceLock<Actor> = OnceLock::new();
    ACTOR.get_or_init(Actor::spawn)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_run_on_one_thread_and_see_each_other() {
        let actor = actor();
        let first = actor.run(|state| state.open(slugline_document::Document::blank()));
        let second = actor.run(|state| state.open(slugline_document::Document::blank()));
        assert_ne!(first, second, "handles are distinct");

        let thread = actor.run(|_| std::thread::current().id());
        assert_eq!(
            actor.run(|_| std::thread::current().id()),
            thread,
            "every command runs on the same thread"
        );
        assert_ne!(thread, std::thread::current().id());

        actor.run(move |state| state.close(first));
        actor.run(move |state| state.close(second));
    }

    #[test]
    fn commands_from_several_threads_are_serialised() {
        // 64 concurrent opens must produce 64 distinct handles: the counter is
        // only safe because nothing else touches it while a command runs.
        let handles: Vec<u64> = std::thread::scope(|scope| {
            let workers: Vec<_> = (0..64)
                .map(|_| {
                    scope.spawn(|| {
                        actor().run(|state| state.open(slugline_document::Document::blank()))
                    })
                })
                .collect();
            workers.into_iter().map(|w| w.join().unwrap()).collect()
        });

        let mut sorted = handles.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), handles.len());

        for handle in handles {
            actor().run(move |state| state.close(handle));
        }
    }
}
