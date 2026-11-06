"""Synthetic, bounded metadata and IPC for the observer memory regression.

No real Codex files or services are read. All fixture files live in argv[1].
"""
import json
import os
import selectors
import shutil
import socket
import sqlite3
import struct
import sys
import time
import uuid

home = sys.argv[1]
local = "11111111-1111-7111-8111-111111111111"
host = "remote-ssh-codex-managed:" + "Synthetic" * 18
os.mkdir(os.path.join(home, "ipc"))
os.mkdir(os.path.join(home, "sessions"))
rollout = os.path.join(home, "sessions", "fixture.jsonl")
with open(rollout, "w") as f:
    f.write(json.dumps({"type": "session_meta", "payload": {"id": local}}) + "\n")
db = sqlite3.connect(os.path.join(home, "state_5.sqlite"))
db.execute("CREATE TABLE threads(id,name,title,rollout_path,archived,agent_path,source,recency_at_ms,updated_at_ms,updated_at)")
db.execute("INSERT INTO threads VALUES(?,?,?, ?,0,NULL,'cli',1,1,1)", (local, "Memory fixture", "Memory fixture", rollout))
db.commit()
db.close()
memberships = {str(uuid.UUID(int=index + 1)): host for index in range(25000)}


def write_metadata(generation):
    # The changing high-sorting ID must be rediscovered by a later index scan.
    marker = "ffffffff-ffff-7fff-8fff-%012x" % generation
    temporary = os.path.join(home, "metadata.tmp")
    with open(temporary, "w") as f:
        json.dump({"thread-project-membership-host-ids": {**memberships, marker: host}}, f)
    os.replace(temporary, os.path.join(home, ".codex-global-state.json"))


write_metadata(0)
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(os.path.join(home, "ipc/ipc.sock"))
server.listen(1)
server.settimeout(10)
print("ready", flush=True)
conn, _ = server.accept()
sel = selectors.DefaultSelector()
sel.register(conn, selectors.EVENT_READ)
sel.register(sys.stdin, selectors.EVENT_READ)
pending = bytearray()
next_append = time.monotonic()
deadline = time.monotonic() + 90
sequence = 0
marker_discoveries = set()
clean_on_exit = True


def send(message):
    body = json.dumps(message).encode()
    conn.sendall(struct.pack("<I", len(body)) + body)


try:
    while time.monotonic() < deadline:
        if time.monotonic() >= next_append:
            # Exercise the incremental JSONL parser as well as global metadata.
            sequence += 1
            row = {"type": "event_msg", "timestamp": "2026-01-01T00:00:00Z",
                   "payload": {"type": "agent_message", "message": "fixture-sequence:%d" % sequence,
                               "padding": "x" * 2048}}
            with open(rollout, "a") as f:
                f.write((json.dumps(row) + "\n") * 48)
            if sequence % 6 == 0:
                write_metadata(sequence // 6)
            next_append += 1
        for key, _ in sel.select(0.05):
            if key.fileobj is sys.stdin:
                # EOF means the guarded Swift process was killed. Only a normal
                # stop keeps the summary for its parent to inspect and remove.
                clean_on_exit = sys.stdin.readline().strip() != "stop"
                raise EOFError()
            chunk = conn.recv(65536)
            if not chunk:
                raise EOFError()
            pending.extend(chunk)
            while len(pending) >= 4:
                size = struct.unpack("<I", pending[:4])[0]
                if size > 1024 * 1024:
                    raise RuntimeError("Unexpected fixture frame size")
                if len(pending) < size + 4:
                    break
                message = json.loads(pending[4:size + 4])
                del pending[:size + 4]
                method = message.get("method")
                if method == "initialize":
                    send({"type": "response", "requestId": message["requestId"], "resultType": "success",
                          "result": {"clientId": "fixture-client"}})
                elif method == "thread-owner-discovery":
                    is_local = message["params"]["hostId"] == "local"
                    thread = message["params"]["conversationId"]
                    if thread.startswith("ffffffff-"):
                        marker_discoveries.add(thread)
                    send({"type": "response", "requestId": message["requestId"],
                          "resultType": "success" if is_local else "error", "handledByClientId": "owner-local"})
                elif method == "thread-stream-following-changed":
                    if message["params"]["following"]:
                        send({"type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
                              "sourceClientId": "owner-local", "params": {"hostId": "local", "conversationId": local,
                              "change": {"type": "snapshot", "revision": 1, "conversationState": {
                                  "title": "Memory fixture", "parentThreadId": None,
                                  "threadRuntimeStatus": {"type": "active", "activeFlags": []}, "turns": [], "requests": []}}}})
                else:
                    raise RuntimeError("Unexpected IPC operation")
except (EOFError, BrokenPipeError):
    pass
finally:
    conn.close()
    server.close()
    if clean_on_exit:
        shutil.rmtree(home, ignore_errors=True)
    else:
        with open(os.path.join(home, "memory-summary.json"), "w") as f:
            json.dump({"markerDiscoveries": len(marker_discoveries)}, f)
