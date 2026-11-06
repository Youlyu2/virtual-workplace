#!/usr/bin/env python3
"""Exercise the guard's containment and external-PID read-only contract."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


GUARD = Path(__file__).resolve().parents[1] / "scripts" / "guard-memory.py"


class MemoryGuardTests(unittest.TestCase):
    def run_guard(self, *args):
        result = subprocess.run([sys.executable, str(GUARD), *args],
                                capture_output=True, text=True, timeout=12)
        events = [json.loads(line) for line in result.stderr.splitlines() if line.startswith("{")]
        self.assertTrue(events, result.stderr)
        return result, events[-1]

    def test_child_exit_status(self):
        result, summary = self.run_guard("--interval", ".05", "--", sys.executable,
                                         "-c", "raise SystemExit(7)")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(summary["reason"], "exited")

    def test_memory_limit_stops_owned_child(self):
        result, summary = self.run_guard("--limit-mib", "32", "--interval", ".05", "--",
            sys.executable, "-c", "import time; data=bytearray(64*1024*1024); time.sleep(10)")
        self.assertEqual(result.returncode, 125)
        self.assertEqual(summary["reason"], "memory_limit")
        self.assertGreaterEqual(summary["peak_footprint_mib"], 32)
        with self.assertRaises(ProcessLookupError):
            os.kill(summary["pid"], 0)

    def test_timeout_stops_owned_child(self):
        result, summary = self.run_guard("--timeout", ".15", "--interval", ".05", "--",
            sys.executable, "-c", "import time; time.sleep(10)")
        self.assertEqual(result.returncode, 124)
        self.assertEqual(summary["reason"], "timeout")
        with self.assertRaises(ProcessLookupError):
            os.kill(summary["pid"], 0)

    def test_over_limit_external_pid_is_never_signalled(self):
        result, summary = self.run_guard("--pid", str(os.getpid()), "--limit-mib", "1")
        self.assertEqual(result.returncode, 125)
        self.assertEqual(summary["mode"], "observe")
        self.assertEqual(summary["reason"], "memory_limit")
        os.kill(os.getpid(), 0)


if __name__ == "__main__":
    unittest.main()
