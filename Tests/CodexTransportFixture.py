"""Bounded IPC test peer. Uses only the temporary fixture directory passed in."""
import json, os, selectors, socket, sqlite3, struct, sys, time

home = sys.argv[1]
local = "11111111-1111-7111-8111-111111111111"
remote = "22222222-2222-7222-8222-222222222222"
host = "remote-ssh-codex-managed:Fixture"
os.mkdir(os.path.join(home, "ipc"))
db = sqlite3.connect(os.path.join(home, "state_5.sqlite"))
db.execute("CREATE TABLE threads(id,name,title,rollout_path,archived,agent_path,source,recency_at_ms,updated_at_ms,updated_at)")
db.execute("INSERT INTO threads VALUES(?,?,?,NULL,0,NULL,'cli',1,1,1)", (local, "Local fixture", "Local fixture"))
db.commit(); db.close()
with open(os.path.join(home, ".codex-global-state.json"), "w") as f:
    json.dump({"thread-project-membership-host-ids": {remote: host},
               "codex-managed-remote-connections": [{"hostId": host, "displayName": "Fixture DevBox"}]}, f)
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(os.path.join(home, "ipc/ipc.sock")); server.listen(1)
server.settimeout(8)
print("ready", flush=True)
conn, _ = server.accept()
sel = selectors.DefaultSelector(); sel.register(conn, selectors.EVENT_READ); sel.register(sys.stdin, selectors.EVENT_READ)
pending = bytearray(); available = True; follows = 0; methods = set(); deadline = time.monotonic() + 8

def send(message):
    body = json.dumps(message).encode()
    conn.sendall(struct.pack("<I", len(body)) + body)

def change(value):
    send({"type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
          "sourceClientId": "owner-remote", "params": {"hostId": host, "conversationId": remote, "change": value}})

def snapshot(thread, target, revision=1, title=None):
    state = {"title": title or ("Local fixture" if target == "local" else "Remote fixture"),
             "parentThreadId": None, "threadRuntimeStatus": {"type": "active", "activeFlags": []}, "turns": [], "requests": []}
    send({"type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
          "sourceClientId": "owner-local" if target == "local" else "owner-remote",
          "params": {"hostId": target, "conversationId": thread, "change": {"type": "snapshot", "revision": revision, "conversationState": state}}})

try:
    while time.monotonic() < deadline:
        for key, _ in sel.select(0.05):
            if key.fileobj is sys.stdin:
                command = sys.stdin.readline().strip()
                if command == "stop" or not command: raise EOFError()
                if command == "gap":
                    for base, revision in [(999, 1000), (1, 2), (2, 3)]:
                        change({"type": "patches", "baseRevision": base, "revision": revision,
                                "patches": [{"op": "replace", "path": ["title"], "value": "Stale remote title"}]})
                elif command == "fresh": snapshot(remote, host, 10, "Remote recovered")
                elif command == "unload":
                    change({"type": "patches", "baseRevision": 10, "revision": 11,
                            "patches": [{"op": "replace", "path": ["threadRuntimeStatus"], "value": {"type": "notLoaded", "activeFlags": []}}]})
                elif command == "fail": available = False
                else: raise RuntimeError("Unknown fixture command")
                continue
            chunk = conn.recv(65536)
            if not chunk: raise EOFError()
            pending.extend(chunk)
            while len(pending) >= 4:
                size = struct.unpack("<I", pending[:4])[0]
                if size > 1024 * 1024: raise RuntimeError("Unexpected fixture frame size")
                if len(pending) < size + 4: break
                message = json.loads(pending[4:size + 4]); del pending[:size + 4]
                method = message.get("method"); methods.add(method)
                if method == "initialize":
                    send({"type": "response", "requestId": message["requestId"], "resultType": "success", "result": {"clientId": "fixture-client"}})
                elif method == "thread-owner-discovery":
                    target = message["params"]["hostId"]
                    send({"type": "response", "requestId": message["requestId"],
                          "resultType": "error" if target == host and not available else "success",
                          "handledByClientId": "owner-local" if target == "local" else "owner-remote"})
                elif method == "thread-stream-following-changed":
                    params = message["params"]
                    if params["following"]:
                        if params["hostId"] == "local": snapshot(local, "local")
                        else:
                            follows += 1
                            if follows == 1: snapshot(remote, host)
                else: raise RuntimeError("Observer attempted an unexpected IPC operation")
except (EOFError, BrokenPipeError):
    pass
finally:
    with open(os.path.join(home, "peer-summary.json"), "w") as f:
        json.dump({"remoteFollows": follows, "methods": sorted(methods)}, f)
    conn.close(); server.close()
