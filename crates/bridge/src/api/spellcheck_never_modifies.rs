//! Phase 9's named invariant: every spell surface is read-only unless the
//! writer explicitly chooses a replacement edit.

use std::future::Future;
use std::path::PathBuf;
use std::pin::pin;
use std::sync::Arc;
use std::task::{Context, Poll, Wake, Waker};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::actor::actor;
use crate::api::doc::{doc_blocks, doc_close, doc_source, DocumentHandle};
use crate::api::files::doc_dirty;
use crate::api::spell::{
    spell_add_personal, spell_add_project, spell_check_block, spell_ignore_all, spell_ignore_once,
    spell_suggest, SpellActionResult,
};

struct TestWake(std::thread::Thread);

impl Wake for TestWake {
    fn wake(self: Arc<Self>) {
        self.0.unpark();
    }
}

fn block_on<T>(future: impl Future<Output = T>) -> T {
    let waker = Waker::from(Arc::new(TestWake(std::thread::current())));
    let mut context = Context::from_waker(&waker);
    let mut future = pin!(future);
    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(value) => return value,
            Poll::Pending => std::thread::yield_now(),
        }
    }
}

fn temp_dir() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "slugline-spell-invariant-{}-{nonce}",
        std::process::id()
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
}

#[test]
fn spellcheck_never_modifies() {
    let _serial = super::spell_test_lock();
    let root = temp_dir();
    let script = root.join("invariant.fountain");
    let personal = root.join("personal.dic");
    let project = slugline_spell::project_dictionary_path(&script);
    let source = "Wurld stays exactly as typed.\n";
    std::fs::write(&script, source).unwrap();
    let handle = actor().run({
        let script = script.clone();
        let personal = personal.clone();
        move |state| {
            state.spelling_mut().personal_path = Some(personal);
            let id = state.open(slugline_document::Document::parse(source));
            state
                .session_mut(id)
                .expect("the document was just opened")
                .set_file(script, "spell-invariant".to_owned());
            DocumentHandle { id }
        }
    });
    let block = doc_blocks(handle, 0, 1)[0].id;
    let before = doc_source(handle);
    assert!(!doc_dirty(handle));

    let _ = block_on(spell_check_block(handle, block));
    let _ = block_on(spell_suggest("Wurld".to_owned()));
    assert_eq!(
        spell_ignore_once(handle, block, 0, 5, "Wurld".to_owned()),
        SpellActionResult::Applied
    );
    assert_eq!(
        spell_ignore_all(handle, "Wurld".to_owned()),
        SpellActionResult::Applied
    );
    assert_eq!(
        block_on(spell_add_personal("Wurld".to_owned())),
        SpellActionResult::Applied
    );
    assert_eq!(
        block_on(spell_add_project(handle, "Wurld".to_owned())),
        SpellActionResult::Applied
    );
    assert_eq!(std::fs::read_to_string(&personal).unwrap(), "wurld\n");
    assert_eq!(std::fs::read_to_string(&project).unwrap(), "wurld\n");
    std::fs::remove_file(&project).unwrap();
    let _ = block_on(spell_check_block(handle, block));

    assert_eq!(doc_source(handle), before);
    assert_eq!(before, source);
    assert!(
        !doc_dirty(handle),
        "dictionary and ignore actions never dirty the screenplay, even when a sidecar disappears"
    );

    doc_close(handle);
    actor().run(|state| *state.spelling_mut() = Default::default());
    let _ = std::fs::remove_dir_all(root);
}
