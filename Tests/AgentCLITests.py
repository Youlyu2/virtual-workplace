#!/usr/bin/env python3
"""Exercise the actual CLI, Foundation mailbox and shared-state writer together."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time


PROJECT = Path(__file__).resolve().parents[1]
CLI = PROJECT / "scripts" / "workplace-agent.py"
HOST = PROJECT / "build" / "AgentControlFixtureHost"
checks = 0


def expect(condition, message):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(message)


def main():
    with tempfile.TemporaryDirectory(prefix="agent-cli-") as temporary:
        root = Path(temporary)
        (root / ".agent-test-fixture").write_text("synthetic-avatar-only")
        host = subprocess.Popen([str(HOST), str(root)], cwd=PROJECT,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            expect(host.stdout.readline().strip() == "READY", "the isolated numeric host publishes startup status")
            acknowledgements = []

            def cli(*arguments, code=0):
                result = subprocess.run([sys.executable, str(CLI), "--state-dir", str(root), *arguments],
                                        capture_output=True, text=True, timeout=3)
                expect(result.returncode == code, f"CLI {arguments[0]} exited{result.returncode}: {result.stderr}")
                value = json.loads(result.stdout)
                if arguments[0] != "status":
                    expect(value.get("ok") == (code == 0), "the command acknowledgement matches success or rejection")
                    acknowledgements.append(value["id"])
                return value

            def wait_pose(predicate):
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    current = json.loads((root / "agent-status.json").read_text())
                    if predicate(current["pose"]):
                        return current
                    time.sleep(0.02)
                raise AssertionError("avatar did not reach its arbitrary numeric target")

            initial = cli("status")
            expect(initial["mode"] == "automatic" and initial["statusAgeSeconds"] < 2,
                   "a fresh read-only status describes the original controller")
            expect(len(initial["capabilities"]["jointLimits"]) == 12,
                   "the CLI exposes numeric capabilities for all12joints")
            takeover = cli("mode", "agent")
            expect(takeover["result"]["mode"] == "agent", "CLI takeover grants avatar ownership")
            pose = {"facing": "front", "joints": {"leftShoulder": -37.25, "rightElbow": 24.5},
                    "face": {"eyes": 0.4, "brows": -0.35, "mouth": 0.8}}
            cli("pose", json.dumps(pose), "--duration", ".2")
            reached = wait_pose(lambda value: value["joints"].get("leftShoulder") == -37.25)
            expect(reached["pose"]["face"]["mouth"] == 0.8 and reached["pose"]["facing"] == "front",
                   "fractional limb and expression targets reach the active pose")
            state = json.loads((root / "state.json").read_text())
            expect(state["employeeControlMode"] == "agent" and len(state["agentTimeline"]["frames"]) == 2,
                   "Inbox changes persist through the production StateStore")
            cli("pose", json.dumps({"face": {"brows": 0.125}}), "--duration", ".15")
            partial = wait_pose(lambda value: value["face"]["brows"] == 0.125)
            expect(partial["pose"]["joints"].get("leftShoulder") == -37.25
                   and partial["pose"]["face"]["eyes"] == 0.4,
                   "a CLI partial target preserves the current limb and eye parameters")
            frames = [{"time": 0.2, "pose": {"joints": {"leftHip": -10.5, "rightHip": 15.125}}},
                      {"time": 0.4, "pose": {"face": {"mouth": -0.65, "brows": 0.72}}}]
            sequence = cli("sequence", json.dumps(frames))
            expect(sequence["result"]["duration"] == 0.4, "the CLI submits a free numeric keyframe sequence")
            completed = wait_pose(lambda value: value["face"]["mouth"] == -0.65)
            expect(completed["pose"]["joints"].get("rightHip") == 15.125,
                   "later sparse sequence frames preserve independently controlled leg targets")
            state = json.loads((root / "state.json").read_text())
            expect(len(state["agentTimeline"]["frames"]) == 3,
                   "the shared snapshot carries only the current bounded trajectory")
            release = cli("mode", "automatic")
            expect(release["result"]["mode"] == "automatic", "CLI release returns avatar ownership")
            stable_state = (root / "state.json").read_bytes()
            rejected = cli("pose", json.dumps({"joints": {"leftShoulder": 1}}), code=1)
            expect("Agent" in rejected.get("error", ""), "a released controller receives a useful explicit rejection")
            expect((root / "state.json").read_bytes() == stable_state,
                   "a rejected external command cannot change the persisted pose or control mode")
            expect(len(set(acknowledgements)) == len(acknowledgements), "every CLI request has a fresh matching UUID")
            print(f"PASS: {checks} actual CLI/Inbox/StateStore end-to-end checks (isolated, no graphics)")
        finally:
            (root / "stop").touch()
            try:
                host.wait(timeout=2)
            except subprocess.TimeoutExpired:
                host.terminate()
                host.wait(timeout=2)
            if host.returncode:
                raise RuntimeError(f"isolated host exited{host.returncode}: {host.stderr.read()}")


if __name__ == "__main__":
    main()
