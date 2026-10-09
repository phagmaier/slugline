#!/usr/bin/env python3
"""Failure-only worker for check_runtime_budgets.py; never a startup probe.

Xlib runs in a bounded subprocess: an unresponsive X server must not prevent
native stacks or disposable-process cleanup. No graphics context is created.
"""

import ctypes as C
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

OUTPUT_BYTES = 128 * 1024
MAX_THREADS = 256
MAX_WINDOWS = 256


def read_proc(path, limit=4096):
    try:
        with path.open("rb") as stream:
            data = stream.read(limit + 1)
        return {"text": data[:limit].decode(errors="replace"), "truncated": len(data) > limit}
    except OSError as error:
        return {"error": str(error)}


def command(args, timeout):
    record = {"args": args, "timeout_seconds": timeout, "started_monotonic_ns": time.monotonic_ns()}
    # Files bound retained output without buffering unbounded debugger output.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            process = subprocess.Popen(args, stdout=stdout, stderr=stderr)
            try:
                process.wait(timeout=timeout)
                record["status"] = "completed"
            except subprocess.TimeoutExpired:
                record["status"] = "timeout"
                process.kill()
                process.wait()
            record["returncode"] = process.returncode
        except OSError as error:
            record.update(status="unavailable", error=str(error))
        for name, stream in (("stdout", stdout), ("stderr", stderr)):
            stream.seek(0)
            data = stream.read(OUTPUT_BYTES + 1)
            record[name] = data[:OUTPUT_BYTES].decode(errors="replace")
            record[f"{name}_truncated"] = len(data) > OUTPUT_BYTES
    record["finished_monotonic_ns"] = time.monotonic_ns()
    return record


def process_snapshot(pid):
    proc = Path(f"/proc/{pid}")
    record = {"started_monotonic_ns": time.monotonic_ns()}
    record["process"] = {name: read_proc(proc / name) for name in ("stat", "status", "wchan", "syscall")}
    # Full mappings include Mesa/GL/EGL/Vulkan drivers without guessing their names.
    record["mappings"] = read_proc(proc / "maps", OUTPUT_BYTES)
    record["threads"] = []
    try:
        tasks = sorted((proc / "task").iterdir(), key=lambda task: int(task.name))
        record["thread_count"] = len(tasks)
        record["threads_truncated"] = len(tasks) > MAX_THREADS
        for task in tasks[:MAX_THREADS]:
            record["threads"].append({"tid": int(task.name), **{
                name: read_proc(task / name, 1024) for name in ("comm", "stat", "wchan", "syscall")
            }})
    except OSError as error:
        record["threads_error"] = str(error)
    record["finished_monotonic_ns"] = time.monotonic_ns()
    return record


def window_tree():
    # XWindowAttributes from Xlib.h; native XIDs and longs are unsigned long.
    class Attributes(C.Structure):
        _fields_ = [
            *[(name, C.c_int) for name in ("x", "y", "width", "height", "border_width", "depth")],
            ("visual", C.c_void_p), ("root", C.c_ulong),
            *[(name, C.c_int) for name in ("class_", "bit_gravity", "win_gravity", "backing_store")],
            ("backing_planes", C.c_ulong), ("backing_pixel", C.c_ulong),
            ("save_under", C.c_int), ("colormap", C.c_ulong),
            ("map_installed", C.c_int), ("map_state", C.c_int),
            *[(name, C.c_long) for name in ("all_event_masks", "your_event_mask", "do_not_propagate_mask")],
            ("override_redirect", C.c_int), ("screen", C.c_void_p),
        ]

    lib = C.CDLL("libX11.so.6")
    xid = C.c_ulong
    pointer = C.c_void_p
    # Explicit signatures prevent truncating 64-bit display/data pointers.
    signatures = {
        "XOpenDisplay": (pointer, [C.c_char_p]),
        "XDefaultRootWindow": (xid, [pointer]),
        "XInternAtom": (xid, [pointer, C.c_char_p, C.c_int]),
        "XGetWindowAttributes": (C.c_int, [pointer, xid, C.POINTER(Attributes)]),
        "XGetWindowProperty": (C.c_int, [pointer, xid, xid, C.c_long, C.c_long, C.c_int, xid,
                                         C.POINTER(xid), C.POINTER(C.c_int), C.POINTER(xid),
                                         C.POINTER(xid), C.POINTER(pointer)]),
        "XFetchName": (C.c_int, [pointer, xid, C.POINTER(pointer)]),
        "XQueryTree": (C.c_int, [pointer, xid, C.POINTER(xid), C.POINTER(xid),
                                C.POINTER(C.POINTER(xid)), C.POINTER(C.c_uint)]),
        "XFree": (C.c_int, [pointer]),
        "XCloseDisplay": (C.c_int, [pointer]),
    }
    for name, (result, args) in signatures.items():
        function = getattr(lib, name)
        function.restype, function.argtypes = result, args
    on_error_type = C.CFUNCTYPE(C.c_int, pointer, pointer)
    errors = []

    @on_error_type
    def on_error(display, event):
        if len(errors) < MAX_WINDOWS:
            errors.append("X request failed (window may have disappeared)")
        return 0

    lib.XSetErrorHandler.argtypes = [on_error_type]
    lib.XSetErrorHandler.restype = pointer
    lib.XSetErrorHandler(on_error)
    display = lib.XOpenDisplay(None)
    if not display:
        raise RuntimeError("XOpenDisplay failed")
    rows = []
    pending = [(lib.XDefaultRootWindow(display), None, 0)]
    truncated = False
    try:
        atom = lib.XInternAtom(display, b"_NET_WM_PID", 0)
        while pending and len(rows) < MAX_WINDOWS:
            window, parent, depth = pending.pop()
            attributes = Attributes()
            if not lib.XGetWindowAttributes(display, window, C.byref(attributes)):
                continue
            row = {"xid": window, "parent": parent, "depth": depth,
                   "map_state": attributes.map_state,
                   "map_state_name": {0: "unmapped", 1: "unviewable", 2: "viewable"}.get(attributes.map_state),
                   "width": attributes.width, "height": attributes.height, "_NET_WM_PID": None}
            actual_type, count, remaining = xid(), xid(), xid()
            format_ = C.c_int()
            data = pointer()
            status = lib.XGetWindowProperty(display, window, atom, 0, 1, 0, 0,
                                           C.byref(actual_type), C.byref(format_), C.byref(count),
                                           C.byref(remaining), C.byref(data))
            try:
                if status == 0 and data and format_.value == 32 and count.value:
                    row["_NET_WM_PID"] = C.cast(data, C.POINTER(xid))[0]
                elif status or actual_type.value:
                    row["pid_property_error"] = {"status": status, "type": actual_type.value, "format": format_.value}
            finally:
                if data:
                    lib.XFree(data)
            name = pointer()
            if lib.XFetchName(display, window, C.byref(name)) and name:
                row["name"] = C.string_at(name).decode(errors="replace")[:512]
                lib.XFree(name)
            rows.append(row)
            root, parent_id = xid(), xid()
            children = C.POINTER(xid)()
            count_children = C.c_uint()
            if lib.XQueryTree(display, window, C.byref(root), C.byref(parent_id), C.byref(children), C.byref(count_children)):
                try:
                    slots = MAX_WINDOWS - len(rows) - len(pending)
                    take = min(count_children.value, max(0, slots)) if depth < 16 else 0
                    truncated |= take < count_children.value
                    pending.extend((children[i], window, depth + 1) for i in range(take))
                finally:
                    if children:
                        lib.XFree(children)
        truncated |= bool(pending)
    finally:
        lib.XCloseDisplay(display)
    return {"windows": rows, "truncated": truncated, "errors": errors}


def capture(pid):
    report = {"proc": process_snapshot(pid)}
    report["window_tree"] = command([sys.executable, __file__, "--windows"], 2)
    tree = report["window_tree"]
    if tree.get("returncode") == 0 and not tree["stdout_truncated"]:
        try:
            tree["tree"] = json.loads(tree["stdout"])
            del tree["stdout"]
        except ValueError as error:
            tree["parse_error"] = str(error)
    # Never contact debuginfod or load application-provided debugger scripts.
    os.environ["DEBUGINFOD_URLS"] = ""
    report["native_stacks"] = command([
        "gdb", "-q", "-nx", "-nh", "-batch",
        "-iex", "set auto-load off", "-iex", "set debuginfod enabled off",
        "-ex", "set pagination off", "-p", str(pid),
        "-ex", "info threads", "-ex", "thread apply all bt 12", "-ex", "detach",
    ], 5)
    return report


if __name__ == "__main__":
    result = window_tree() if sys.argv[1] == "--windows" else capture(int(sys.argv[1]))
    print(json.dumps(result), flush=True)
