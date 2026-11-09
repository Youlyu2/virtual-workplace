#!/usr/bin/env python3
"""Control the avatar through a local, single-command mailbox.

The app must be running. Commands affect avatar pose only, never real Codex
tasks or notes. Angles/expressions accept arbitrary valid numeric targets.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import uuid


DEFAULT = Path.home() / "Library/Application Support/VirtualWorkplace"


def atomic_json(path, value):
    data = json.dumps(value, ensure_ascii=False, allow_nan=False).encode()
    if len(data) > 65536:
        raise ValueError("Command exceeds 64 KiB")
    fd, name = tempfile.mkstemp(prefix=".agent-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, default=DEFAULT)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="Read current pose, mode and numeric limits")
    mode = commands.add_parser("mode", help="Select avatar ownership")
    mode.add_argument("value", choices=("automatic", "agent"))
    pose = commands.add_parser("pose", help="Apply a partial pose as a smooth target")
    pose.add_argument("json", help='e.g. {"facing":"front","joints":{"leftShoulder":-80},"face":{"mouth":0.8}}')
    pose.add_argument("--duration", type=float, default=1.5)
    sequence = commands.add_parser("sequence", help="Set up to 31 timed arbitrary pose patches, within 15 seconds")
    sequence.add_argument("json", help='[{"time":1,"pose":{"joints":{"rightElbow":80}}},...]')
    args = parser.parse_args()
    root = args.state_dir.expanduser().resolve()
    if args.command == "status":
        path = root / "agent-status.json"
        if not path.is_file() or path.stat().st_size > 65536:
            raise ValueError("No local Agent status. Start the app version with Agent control support.")
        value = json.loads(path.read_text())
        value["statusAgeSeconds"] = round(max(0, time.time() - value.get("updatedAt", 0)), 2)
        print(json.dumps(value, ensure_ascii=False, indent=2))
        return 0
    if not root.is_dir():
        raise ValueError("State directory does not exist. Start the app first.")
    request = {"id": str(uuid.uuid4()), "issuedAt": time.time(), "op": args.command}
    if args.command == "mode":
        request["mode"] = args.value
    elif args.command == "pose":
        request.update(pose=json.loads(args.json), duration=args.duration)
    else:
        request["frames"] = json.loads(args.json)
    lock_path = root / "agent-client.lock"
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another Agent command is awaiting a response. Retry after it finishes.")
        atomic_json(root / "agent-command.json", request)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            try:
                result_path = root / "agent-result.json"
                if result_path.stat().st_size <= 65536:
                    result = json.loads(result_path.read_text())
                    if result.get("id") == request["id"]:
                        print(json.dumps(result, ensure_ascii=False, indent=2))
                        return 0 if result.get("ok") else 1
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.05)
    raise ValueError("App did not acknowledge within 8 seconds. Check that the updated app is running.")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
