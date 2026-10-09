#!/usr/bin/env python3
"""Close the shipped Linux release process the ordinary way (ADR 0053).

    xvfb-run -a python3 tools/check_clean_close.py

Every close is a WM_DELETE_WINDOW sent while a frame is still being drawn: the
library sliding in after Ctrl+W, a dialog fading in over the script, and focus
moving through the library. Each process must exit zero by itself. A signal, a
close that needs terminating and a script whose bytes are not what was saved
are all failures. The second launch edits what the first one saved, so its
bytes also prove what the reopened editor held. The third names no script and
must come back to the one the second was closed in, which it puts away to
reach the library. Each run has fresh XDG directories and a disposable CRLF
script.
"""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
from managed_fixture import create_project
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # The import below must not leave tools/__pycache__.
from check_runtime_budgets import BudgetFailure, sample, wait_open, xdotool  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "app/build/linux/x64/release/bundle/slugline"
RUNS = 5
SOURCE = b"INT. CHECK - DAY\r\n\r\nA river meets another river.\r\n"
EDIT = " Again"
READY_SECONDS = 60
EXIT_SECONDS = 15


class CloseFailure(RuntimeError):
    pass


class _Data(ctypes.Union):
    _fields_ = [("l", ctypes.c_long * 5)]


class _ClientMessage(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int), ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
        ("format", ctypes.c_int), ("data", _Data),
    ]


class _Event(ctypes.Union):
    _fields_ = [("xclient", _ClientMessage), ("pad", ctypes.c_long * 24)]


def request_close(window):
    """What a window manager's close button sends. `xdotool windowclose` is
    XDestroyWindow instead, which takes the drawable from under the app."""
    xlib = ctypes.CDLL("libX11.so.6")
    xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    xlib.XOpenDisplay.restype = ctypes.c_void_p
    xlib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    xlib.XInternAtom.restype = ctypes.c_ulong
    xlib.XSendEvent.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long,
        ctypes.POINTER(_Event),
    ]
    xlib.XFlush.argtypes = [ctypes.c_void_p]
    xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    display = xlib.XOpenDisplay(os.environ["DISPLAY"].encode())
    if not display:
        raise CloseFailure(f"cannot open X display {os.environ['DISPLAY']}")
    event = _Event()
    event.xclient.type = 33  # ClientMessage
    event.xclient.send_event = 1
    event.xclient.display = display
    event.xclient.window = int(window)
    event.xclient.message_type = xlib.XInternAtom(display, b"WM_PROTOCOLS", 0)
    event.xclient.format = 32
    event.xclient.data.l[0] = xlib.XInternAtom(display, b"WM_DELETE_WINDOW", 0)
    sent = xlib.XSendEvent(display, int(window), 0, 0, ctypes.byref(event))
    xlib.XFlush(display)
    xlib.XCloseDisplay(display)
    if not sent:
        raise CloseFailure("WM_DELETE_WINDOW was not sent")


def wait_still(process):
    """Startup work has stopped: three 100 ms samples without a CPU tick."""
    deadline = time.monotonic() + READY_SECONDS
    still, before = 0, sample(process).ticks
    while time.monotonic() < deadline:
        time.sleep(0.1)
        after = sample(process).ticks
        still = still + 1 if after == before else 0
        if still == 3:
            return
        before = after
    raise CloseFailure("the release process never came to rest after startup")


def wait_saved(process, state, script, expected):
    """The Save has finished, not merely written its bytes. The journal starts
    again from the saved text in the actor turn that clears the dirty flag;
    Ctrl+W any earlier is rightly answered with "Save changes?"."""
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        sample(process)
        if script.read_bytes() == expected:
            for journal in (state / "slugline/journal").glob("*"):
                try:
                    lines = journal.read_text().splitlines()
                    base = json.loads(lines[0])["base"]
                    if len(lines) == 1 and base.endswith(f"-{len(expected)}"):
                        return
                except (OSError, ValueError, IndexError, KeyError):
                    pass
        time.sleep(0.01)
    raise CloseFailure(
        f"Save did not finish with the expected bytes: have {script.read_bytes().hex()}, "
        f"want {expected.hex()}"
    )


def wait_put_away(process, state):
    """Ctrl+W has closed the script: its journal, which says a session is
    under way, is gone."""
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        sample(process)
        if not any((state / "slugline/journal").glob("*")):
            return
        time.sleep(0.01)
    raise CloseFailure("Ctrl+W did not put the restored script away")


def session(binary, work, name, script, expected, before_close, record, restored=None):
    """One launch, closed by `before_close`'s frames and a WM_DELETE_WINDOW.

    `restored` is the script a launch that names none must come back to: the
    one the session before it was closed in."""
    entry = {"session": name}
    record["sessions"].append(entry)
    env = os.environ.copy()
    env.pop("WAYLAND_DISPLAY", None)
    env.update(
        GDK_BACKEND="x11", LIBGL_ALWAYS_SOFTWARE="1", LP_NUM_THREADS="4",
        GDK_SCALE="1", GDK_DPI_SCALE="1",
    )
    for kind in ("CONFIG", "DATA", "STATE", "CACHE", "RUNTIME"):
        directory = work / kind.lower()
        directory.mkdir(mode=0o700, exist_ok=True)
        env[f"XDG_{kind}_{'DIR' if kind == 'RUNTIME' else 'HOME'}"] = str(directory)
    prefs = work / "config/slugline"
    prefs.mkdir(exist_ok=True)
    # Only the explicit Save below may write the script.
    (prefs / "prefs.json").write_text(json.dumps({
        "autosave_enabled": False, "library_dir": str(work / "data/slugline/library"),
    }))
    with (work / f"{name}.log").open("w+") as log:
        started = time.monotonic()
        process = subprocess.Popen(
            [str(binary), *([str(script)] if script else [])],
            env=env, stdout=log, stderr=log,
        )
        entry["pid"] = process.pid
        try:
            deadline = time.monotonic() + 10
            while not (windows := xdotool(
                "search", "--onlyvisible", "--pid", process.pid, missing_ok=True
            )):
                sample(process)
                if time.monotonic() > deadline:
                    raise CloseFailure("no first-frame window within 10s")
                time.sleep(0.005)
            window = windows.splitlines()[0]
            xdotool("windowfocus", "--sync", window)
            if script or restored:
                wait_open(process, work / "state", script or restored)
            wait_still(process)
            if restored:
                xdotool("key", "ctrl+w")
                wait_put_away(process, work / "state")
                wait_still(process)
            entry["ready_ms"] = round((time.monotonic() - started) * 1000, 1)
            if script:
                xdotool("key", "ctrl+End")
                xdotool("type", "--delay", "40", EDIT)
                xdotool("key", "ctrl+s")
                wait_saved(process, work / "state", script, expected)
            flood = before_close(env)
            closing = time.monotonic()
            request_close(window)
            try:
                process.wait(timeout=EXIT_SECONDS)
                entry["close_ms"] = round((time.monotonic() - closing) * 1000, 1)
            except subprocess.TimeoutExpired:
                raise CloseFailure(
                    f"still running {EXIT_SECONDS}s after WM_DELETE_WINDOW"
                ) from None
            finally:
                if flood is not None:
                    flood.wait(timeout=10)
            entry["exit"] = process.returncode
            if process.returncode < 0:
                raise CloseFailure(
                    f"killed by {signal.Signals(-process.returncode).name} while closing"
                )
            if process.returncode:
                raise CloseFailure(f"exited with {process.returncode}")
            if script and script.read_bytes() != expected:
                raise CloseFailure("closing changed the saved script bytes")
        except BudgetFailure as error:
            raise CloseFailure(str(error)) from None
        finally:
            # A process this had to stop did not close; that is never a pass.
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                entry["terminated"] = process.returncode
            log.seek(0)
            entry["process_log"] = log.read()
    return entry


def close_document(env):
    xdotool("key", "ctrl+w")


def open_dialog(env):
    xdotool("key", "F1")


def move_focus(env):
    flood = subprocess.Popen(
        ["xdotool", "key", "--delay", "12", "--repeat", "150", "Tab"], env=env
    )
    time.sleep(0.35)  # The stimulus, mid-flood; not a wait for anything to end.
    return flood


def run(args, report):
    if not os.environ.get("DISPLAY") or not shutil.which("xdotool"):
        raise CloseFailure("requires an X display and xdotool; use xvfb-run -a")
    binary = args.binary.resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise CloseFailure(f"build the release bundle first: {binary}")
    report.update(
        binary=str(binary),
        binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
        source_hex=SOURCE.hex(), runs=[],
    )
    saved = SOURCE[:-2] + EDIT.encode() + b"\r\n"
    resaved = SOURCE[:-2] + EDIT.encode() * 2 + b"\r\n"
    for index in range(args.runs):
        record = {"run": index + 1, "sessions": []}
        report["runs"].append(record)
        with tempfile.TemporaryDirectory(prefix="slugline-close-") as tmp:
            work = Path(tmp)
            script = create_project(work, "close", SOURCE)
            closes = [
                session(binary, work, "save-close", script, saved, close_document, record),
                session(binary, work, "reopen", script, resaved, open_dialog, record),
                session(
                    binary, work, "library", None, None, move_focus, record,
                    restored=script,
                ),
            ]
        print(
            f"run {index + 1}/{args.runs}: " + ", ".join(
                f"{entry['session']} exit {entry['exit']} in {entry['close_ms']} ms"
                for entry in closes
            ),
            flush=True,
        )
    print(f"PASS clean close: {args.runs * 3} ordinary closes exited zero", flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--binary", type=Path, default=BINARY,
        help="another bundle's runner, e.g. an installed one or a deliberate regression",
    )
    parser.add_argument("--runs", type=int, default=RUNS)
    parser.add_argument(
        "--output", type=Path,
        help="retain every session's exit status and process log, including failures",
    )
    args = parser.parse_args()
    report = {}
    try:
        result = run(args, report)
    except (CloseFailure, BudgetFailure, OSError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        print(f"FAIL: {error}", file=sys.stderr)
        result = 1
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    return result


if __name__ == "__main__":
    sys.exit(main())
