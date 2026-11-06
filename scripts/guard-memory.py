#!/usr/bin/env python3
"""Run a diagnostic with a macOS physical-footprint limit, or observe a PID.

Examples:
  python3 scripts/guard-memory.py --limit-mib 768 --timeout 120 -- build/MyTest
  python3 scripts/guard-memory.py --pid 1234 --limit-mib 1536 --timeout 60

Physical footprint includes charged compressed memory, which RSS alone misses.
Only a child launched by this script can be terminated. --pid is read-only.
Metrics are JSON lines on stderr; --jsonl also saves them to an explicit path.
Exit codes: child status, 124 timeout, 125 memory limit, 126 measurement error.
"""

import argparse
import ctypes
import ctypes.util
import errno
import json
import os
import subprocess
import sys
import time
from pathlib import Path


MIB = 1024 * 1024


class RusageInfoV2(ctypes.Structure):
    # Layout from the macOS SDK's sys/resource.h (RUSAGE_INFO_V2).
    _fields_ = [("ri_uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "ri_user_time", "ri_system_time", "ri_pkg_idle_wkups",
            "ri_interrupt_wkups", "ri_pageins", "ri_wired_size",
            "ri_resident_size", "ri_phys_footprint", "ri_proc_start_abstime",
            "ri_proc_exit_abstime", "ri_child_user_time", "ri_child_system_time",
            "ri_child_pkg_idle_wkups", "ri_child_interrupt_wkups",
            "ri_child_pageins", "ri_child_elapsed_abstime", "ri_diskio_bytesread",
            "ri_diskio_byteswritten",
        )
    ]


class MemorySampler:
    def __init__(self):
        if sys.platform != "darwin":
            raise RuntimeError("This diagnostic requires macOS proc_pid_rusage")
        self.lib = ctypes.CDLL(ctypes.util.find_library("proc"), use_errno=True)
        self.lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
        self.lib.proc_pid_rusage.restype = ctypes.c_int

    def read(self, pid):
        info = RusageInfoV2()
        if self.lib.proc_pid_rusage(pid, 2, ctypes.byref(info)) != 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))
        return info


def stop_child(child):
    """Never signal an observed/external PID or look up a process by name."""
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pid", type=int, help="Observe this existing PID without sending signals")
    parser.add_argument("--limit-mib", type=float, default=768)
    parser.add_argument("--timeout", type=float, default=120, help="Maximum observation/run duration in seconds")
    parser.add_argument("--interval", type=float, default=1, help="Sample interval in seconds (0.05–60)")
    parser.add_argument("--jsonl", type=Path, help="Write metrics to this file as well as stderr")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if bool(args.pid) == bool(args.command):
        parser.error("Choose exactly one: --pid PID or -- COMMAND [ARGS...]")
    if args.pid is not None and args.pid <= 0:
        parser.error("PID must be positive")
    if not (0 < args.limit_mib < float("inf") and 0 < args.timeout < float("inf")):
        parser.error("Memory limit and timeout must be positive and finite")
    if not 0.05 <= args.interval <= 60:
        parser.error("Sample interval must be between 0.05 and 60 seconds")
    return args


def main():
    args = parse_args()
    # Fail before starting a child if measurement/output setup is unavailable.
    sampler = MemorySampler()
    log = args.jsonl.open("w", encoding="utf-8") if args.jsonl else None
    child = None
    start = time.monotonic()
    peak = 0
    samples = 0
    identity = None

    def emit(record):
        line = json.dumps(record, separators=(",", ":"))
        print(line, file=sys.stderr, flush=True)
        if log:
            print(line, file=log, flush=True)

    def finish(reason, code):
        emit({"event": "summary", "pid": pid, "mode": "observe" if args.pid else "child",
              "reason": reason, "seconds": round(time.monotonic() - start, 3),
              "samples": samples, "peak_footprint_mib": round(peak / MIB, 3), "exit_code": code})
        return code

    try:
        if args.command:
            child = subprocess.Popen(args.command)
        pid = args.pid or child.pid
        while True:
            if child is not None and child.poll() is not None:
                status = child.returncode
                return finish("exited", status if status >= 0 else 128 - status)
            try:
                info = sampler.read(pid)
            except OSError as error:
                if error.errno == errno.ESRCH:
                    # A short-lived child may exit between poll and measurement.
                    if child is not None:
                        status = child.wait()
                        return finish("exited", status if status >= 0 else 128 - status)
                    return finish("process_gone", 0)
                stop_child(child)
                emit({"event": "measurement_error", "errno": error.errno})
                return finish("measurement_error", 126)
            if identity is None:
                identity = info.ri_proc_start_abstime
            elif identity != info.ri_proc_start_abstime:
                # PID reuse must not silently measure a different application.
                return finish("process_replaced", 0)
            elapsed = time.monotonic() - start
            peak = max(peak, info.ri_phys_footprint)
            samples += 1
            emit({"event": "sample", "pid": pid, "seconds": round(elapsed, 3),
                  "footprint_mib": round(info.ri_phys_footprint / MIB, 3),
                  "rss_mib": round(info.ri_resident_size / MIB, 3)})
            if info.ri_phys_footprint >= args.limit_mib * MIB:
                stop_child(child)
                return finish("memory_limit", 125)
            if elapsed >= args.timeout:
                stop_child(child)
                return finish("observed" if args.pid else "timeout", 0 if args.pid else 124)
            time.sleep(min(args.interval, args.timeout - elapsed))
    except KeyboardInterrupt:
        stop_child(child)
        return 130
    finally:
        # Also prevent a diagnostic from being orphaned if this runner errors.
        stop_child(child)
        if log:
            log.close()


if __name__ == "__main__":
    sys.exit(main())
