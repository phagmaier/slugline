#!/usr/bin/env python3
"""Measure the shipped Linux release process (ADR 0050).

    xvfb-run -a python3 tools/check_runtime_budgets.py
    python3 tools/check_runtime_budgets.py --desktop  # manual GPU-session gate

No benchmark entry point or production marker: the GTK runner maps its window
only on Flutter's first frame. All launches have fresh XDG directories. This is
process-cold startup, not a claim about an evicted filesystem cache.
"""

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "app/build/linux/x64/release/bundle/slugline"
REFERENCE = ROOT / "testdata/reference-feature.fountain"
STARTUP_MS = 500
XVFB_RSS_MIB = 320
DESKTOP_RSS_MIB = 250
STARTUP_ATTEMPTS = 5
REFERENCE_SAMPLES = 3
QUIET_SECONDS = 2
IDLE_SECONDS = 10  # Shorter than the permitted 30-second status-line refresh.
SETTLE_TIMEOUT = 60


class BudgetFailure(RuntimeError):
    pass


def xdotool(*args, missing_ok=False):
    result = subprocess.run(
        ["xdotool", *map(str, args)], capture_output=True, text=True, timeout=2
    )
    if result.returncode and not (missing_ok and result.returncode == 1):
        raise BudgetFailure(f"xdotool {' '.join(map(str, args))}: {result.stderr}")
    return result.stdout.strip()


@dataclass
class Sample:
    ticks: int
    rss_kib: int
    threads: dict


def sample(process):
    if process.poll() is not None:
        raise BudgetFailure(f"release process exited with {process.returncode}")
    proc = Path(f"/proc/{process.pid}")
    # comm may contain spaces or ')'; fields after its final ')' start at field 3.
    fields = (proc / "stat").read_text().rsplit(")", 1)[1].split()
    status = dict(
        line.split(":", 1) for line in (proc / "status").read_text().splitlines()
    )
    threads = {}
    for task in (proc / "task").iterdir():
        try:
            values = dict(
                line.split(":", 1) for line in (task / "status").read_text().splitlines()
            )
            threads[task.name] = (
                values["Name"].strip(), int(values["voluntary_ctxt_switches"])
            )
        except FileNotFoundError:
            pass  # The changed thread set still makes this interval nonquiet.
    return Sample(
        int(fields[11]) + int(fields[12]), int(status["VmRSS"].split()[0]), threads
    )


def activity(before, after):
    changed = sorted(before.threads.keys() ^ after.threads.keys())
    wakes = {
        f"{tid}:{after.threads[tid][0]}": after.threads[tid][1] - before.threads[tid][1]
        for tid in before.threads.keys() & after.threads.keys()
        if after.threads[tid][1] != before.threads[tid][1]
    }
    return {
        "cpu_ticks": after.ticks - before.ticks,
        "voluntary_switches": sum(wakes.values()),
        "threads_changed": changed,
        "wakeups_by_thread": wakes,
    }


def quiet(delta):
    return (
        delta["cpu_ticks"] == 0
        and delta["voluntary_switches"] == 0
        and not delta["threads_changed"]
    )


def wait_quiet(process):
    start = time.monotonic()
    before = sample(process)
    quiet_since = start
    while time.monotonic() - start < SETTLE_TIMEOUT:
        time.sleep(0.5)
        after = sample(process)
        delta = activity(before, after)
        if not quiet(delta):
            quiet_since = time.monotonic()
        elif time.monotonic() - quiet_since >= QUIET_SECONDS:
            return round(time.monotonic() - start, 3)
        before = after
    raise BudgetFailure(
        f"idle: no {QUIET_SECONDS}s quiet interval within {SETTLE_TIMEOUT}s; "
        f"last activity: {delta}"
    )


def require_focus(window):
    focused = xdotool("getwindowfocus")
    if focused != window:
        raise BudgetFailure(f"focus lost: expected {window}, got {focused}")


def wait_open(process, state, script):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        sample(process)
        for journal in (state / "slugline/journal").glob("*"):
            try:
                header = json.loads(journal.read_text().splitlines()[0])
                if header.get("script") == str(script):
                    return
            except (OSError, ValueError, IndexError):
                pass
        time.sleep(0.01)
    raise BudgetFailure(f"requested script was not opened and journalled: {script}")


def capture_startup_failure(process, env, start, deadline, record):
    diagnostics = record["startup_diagnostics"] = {
        "launch_before_spawn_monotonic_ns": start,
        "startup_deadline_monotonic_ns": int(deadline * 1_000_000_000),
        "capture_started_monotonic_ns": time.monotonic_ns(),
        "collector_timeout_seconds": 10,
        "environment": {name: env.get(name) for name in (
            "DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY", "GDK_BACKEND",
            "DBUS_SESSION_BUS_ADDRESS", "SESSION_MANAGER", "XDG_SESSION_TYPE",
            "XDG_SESSION_ID", "XDG_CURRENT_DESKTOP", "DESKTOP_SESSION",
            "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME",
            "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "LIBGL_ALWAYS_SOFTWARE",
            "LP_NUM_THREADS", "GDK_SCALE", "GDK_DPI_SCALE", "LD_LIBRARY_PATH",
            "LD_PRELOAD", "LIBGL_DRIVERS_PATH", "MESA_LOADER_DRIVER_OVERRIDE",
            "GALLIUM_DRIVER", "EGL_PLATFORM", "DRI_PRIME", "DEBUGINFOD_URLS",
        )},
    }
    command = [sys.executable, str(ROOT / "tools/startup_diagnostics.py"), str(process.pid)]
    probe_env = env.copy()
    probe_env.pop("LD_PRELOAD", None)  # Do not inject application observers into probes.
    try:
        collector = subprocess.Popen(
            command, env=probe_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            stdout, stderr = collector.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            # Also reap any diagnostic descendants, never the application.
            os.killpg(collector.pid, signal.SIGKILL)
            stdout, stderr = collector.communicate()
            diagnostics["collector_error"] = "collector exceeded 10s"
        diagnostics["collector_returncode"] = collector.returncode
        diagnostics["collector_stderr"] = stderr[:131072].decode(errors="replace")
        if collector.returncode == 0:
            diagnostics["live_state"] = json.loads(stdout)
        else:
            diagnostics["collector_stdout"] = stdout[:131072].decode(errors="replace")
    except Exception as error:
        # Evidence failure must never replace the already-failed startup deadline.
        diagnostics["collector_error"] = f"{type(error).__name__}: {error}"
    finally:
        diagnostics["capture_finished_monotonic_ns"] = time.monotonic_ns()


@contextmanager
def launch(source, desktop, record):
    with tempfile.TemporaryDirectory(prefix="slugline-budgets-") as tmp:
        work = Path(tmp)
        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env["GDK_BACKEND"] = "x11"
        if not desktop:
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
            env["LP_NUM_THREADS"] = "4"
            env["GDK_SCALE"] = "1"
            env["GDK_DPI_SCALE"] = "1"
        for name in ("CONFIG", "DATA", "STATE", "CACHE", "RUNTIME"):
            directory = work / name.lower()
            directory.mkdir(mode=0o700)
            suffix = "DIR" if name == "RUNTIME" else "HOME"
            env[f"XDG_{name}_{suffix}"] = str(directory)
        script = work / ("reference.fountain" if source else "empty.fountain")
        expected = source.read_bytes() if source else b""
        script.write_bytes(expected)
        with (work / "process.log").open("w+") as log:
            start = time.monotonic_ns()
            process = subprocess.Popen(
                [str(BINARY), str(script)], env=env, stdout=log, stderr=log
            )
            record["pid"] = process.pid
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise BudgetFailure(f"release process exited with {process.returncode}")
                    windows = xdotool(
                        "search", "--onlyvisible", "--pid", process.pid, missing_ok=True
                    )
                    if windows:
                        break
                    time.sleep(0.005)
                else:
                    capture_startup_failure(process, env, start, deadline, record)
                    raise BudgetFailure("startup: no first-frame window within 10s")
                record["startup_ms"] = round(
                    (time.monotonic_ns() - start) / 1_000_000, 3
                )
                window = windows.splitlines()[0]
                xdotool("windowfocus", "--sync", window)
                require_focus(window)
                wait_open(process, work / "state", script)
                yield process, window
                if script.read_bytes() != expected:
                    raise BudgetFailure("opening or idle changed the disposable script bytes")
            finally:
                # Disposable sessions only. SIGTERM cleanup is not a clean-exit test.
                cleanup = None
                if "startup_diagnostics" in record:
                    cleanup = record["startup_diagnostics"]["cleanup"] = {
                        "started_monotonic_ns": time.monotonic_ns(), "signals": [],
                    }
                if process.poll() is None:
                    process.terminate()
                    if cleanup is not None:
                        cleanup["signals"].append("SIGTERM")
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        if cleanup is not None:
                            cleanup["signals"].append("SIGKILL")
                        process.wait(timeout=5)
                if cleanup is not None:
                    cleanup.update(
                        returncode=process.returncode,
                        finished_monotonic_ns=time.monotonic_ns(),
                    )
                log.seek(0)
                record["process_log"] = log.read()


def run(args, report):
    if not os.environ.get("DISPLAY") or not shutil.which("xdotool"):
        raise BudgetFailure("requires an X display and xdotool; use xvfb-run -a for the CI profile")
    if not BINARY.is_file() or not os.access(BINARY, os.X_OK):
        raise BudgetFailure(f"build the release bundle first: {BINARY}")
    report.update(
        profile="desktop (manual GPU check)" if args.desktop else "Xvfb / llvmpipe / LP_NUM_THREADS=4",
        clock_ticks_per_second=os.sysconf("SC_CLK_TCK"),
        binary_sha256=hashlib.sha256(BINARY.read_bytes()).hexdigest(),
        reference_sha256=hashlib.sha256(REFERENCE.read_bytes()).hexdigest(),
        launches=[],
        budgets={},
    )
    selected = args.only or ["startup", "idle", "rss"]
    if "startup" in selected:
        measurements = []
        for attempt in range(STARTUP_ATTEMPTS):
            record = {"kind": "empty", "attempt": attempt + 1}
            report["launches"].append(record)
            with launch(None, args.desktop, record):
                pass
            measurements.append(record["startup_ms"])
            print(f"startup {attempt + 1}/{STARTUP_ATTEMPTS}: {measurements[-1]:.3f} ms", flush=True)
        best = min(measurements)
        report["budgets"]["startup"] = dict(
            passed=best < STARTUP_MS, best_ms=best,
            limit_ms=STARTUP_MS, samples_ms=measurements,
        )
    if "idle" in selected or "rss" in selected:
        idle_samples, rss_samples = [], []
        record = {"kind": "reference", "samples": []}
        report["launches"].append(record)
        with launch(REFERENCE, args.desktop, record) as (process, window):
            record["settled_seconds"] = wait_quiet(process)
            print(f"reference settled in {record['settled_seconds']}s", flush=True)
            # Consecutive windows avoid restarting the same startup-cleanup
            # phase for every attempt. One can include the 30s status refresh.
            for index in range(REFERENCE_SAMPLES):
                require_focus(window)
                before = sample(process)
                start = time.monotonic()
                time.sleep(IDLE_SECONDS)
                after = sample(process)
                require_focus(window)
                delta = activity(before, after)
                delta["seconds"] = round(time.monotonic() - start, 3)
                idle_samples.append(delta)
                rss_samples.append(max(before.rss_kib, after.rss_kib) / 1024)
                record["samples"].append(dict(idle=delta, rss_mib=rss_samples[-1]))
                print(
                    f"reference interval {index + 1}/{REFERENCE_SAMPLES}: "
                    f"RSS {rss_samples[-1]:.2f} MiB, idle {delta}",
                    flush=True,
                )
        if "idle" in selected:
            report["budgets"]["idle"] = dict(
                passed=any(quiet(delta) for delta in idle_samples), samples=idle_samples
            )
        if "rss" in selected:
            limit = DESKTOP_RSS_MIB if args.desktop else XVFB_RSS_MIB
            report["budgets"]["rss"] = dict(
                passed=min(rss_samples) < limit, best_mib=min(rss_samples),
                limit_mib=limit, samples_mib=rss_samples,
            )
    for name, result in report["budgets"].items():
        attempts = STARTUP_ATTEMPTS if name == "startup" else REFERENCE_SAMPLES
        reason = (
            "shared-runner scheduling noise" if name == "startup"
            else "late engine cleanup and the permitted 30s status refresh"
        )
        print(
            f"{'PASS' if result['passed'] else 'FAIL'} {name}: {result} "
            f"(best of {attempts}; {reason})",
            flush=True,
        )
    return 0 if all(value["passed"] for value in report["budgets"].values()) else 1


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--desktop", action="store_true",
        help="manual real-desktop profile: preserve the GPU environment, assert 250 MiB",
    )
    parser.add_argument(
        "--only", choices=["startup", "idle", "rss"], action="append",
        help="select a budget for deliberate regression checks",
    )
    parser.add_argument(
        "--output", type=Path,
        help="retain JSON measurements and full process logs, including failures",
    )
    args = parser.parse_args()
    report = {}
    try:
        result = run(args, report)
    except (BudgetFailure, OSError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        print(f"FAIL: {error}", file=sys.stderr)
        result = 1
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    return result


if __name__ == "__main__":
    sys.exit(main())
