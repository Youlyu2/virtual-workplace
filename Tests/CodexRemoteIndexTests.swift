import Foundation
import Darwin

@main
struct CodexRemoteIndexTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    private static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("FAIL: \(message)") }
        catch { checks += 1 }
    }
    private static func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private static func uuid(_ value: Int) -> String { String(format: "%08x-0000-7000-8000-000000000000", value) }

    static func main() throws {
        let thread = uuid(1)
        let host = "remote-ssh-codex-managed:DevBox%20Pro"
        let fixture: [String: Any] = [
            "thread-project-membership-host-ids": [thread: host, uuid(2): "local"],
            "codex-managed-remote-connections": [["hostId": host, "displayName": " DevBox Pro\n ",
                "hostname": "DO_NOT_READ_ENDPOINT", "identity": "DO_NOT_READ_IDENTITY"]],
            "unrelated": ["secret": "DO_NOT_READ_UNRELATED"]
        ]
        let candidates = try CodexRemoteIndex.parse(data: data(fixture))
        expect(candidates == [CodexRemoteCandidate(threadID: thread, hostID: host, hostName: "DevBox Pro")],
               "only remote thread address and sanitized display name are selected")
        expect(CodexThreadIdentity.key(threadID: thread, hostID: "local") == thread,
               "existing local monitor identity is preserved")
        let identity = CodexThreadIdentity.key(threadID: thread, hostID: host)
        expect(identity == CodexThreadIdentity.key(threadID: thread, hostID: host), "remote identity is deterministic")
        expect(identity != thread && identity != CodexThreadIdentity.key(threadID: thread, hostID: "other"),
               "same thread ID on different hosts cannot alias a monitor")
        expect(identity.utf8.count <= 128 && !identity.contains(host), "remote identity is bounded without exposing the host address")
        expect(CodexThreadIdentity.key(threadID: String(repeating: "x", count: 500), hostID: host).utf8.count <= 128,
               "unexpected long thread IDs cannot produce oversized remote scene identities")

        var invalid: [String: Any] = ["not-a-uuid": host, uuid(3): "", uuid(4): "local",
            uuid(5): "remote\nsecret", uuid(6): String(repeating: "猫", count: 86),
            uuid(7): 1, uuid(8): " remote "]
        invalid[uuid(0xabc).uppercased()] = "remote-control:host"
        invalid[uuid(0xabc)] = "remote-control:host"
        let filtered = try CodexRemoteIndex.parse(data: data(["thread-project-membership-host-ids": invalid]))
        expect(filtered.count == 1 && filtered[0].threadID == uuid(0xabc), "invalid IDs, invalid hosts and local hints are excluded, with case-normalized UUIDs deduplicated")
        expect(filtered.first?.hostName == nil, "unknown remote names remain absent")
        let empty = try CodexRemoteIndex.parse(data: data([:]))
        expect(empty.isEmpty, "no configured remote hosts produces an empty index")
        let longName = String(repeating: "长", count: 100)
        let bounded = try CodexRemoteIndex.parse(data: data([
            "thread-project-membership-host-ids": [thread: host],
            "codex-managed-remote-connections": [["hostId": host, "displayName": longName]]]))
        expect(bounded[0].hostName?.count == 80, "display names are bounded for shared scene state")
        rejects("malformed metadata is rejected") { _ = try CodexRemoteIndex.parse(data: Data("{".utf8)) }
        rejects("wrong root shape is rejected") { _ = try CodexRemoteIndex.parse(data: data([])) }
        rejects("wrong hint shape is rejected instead of deleting a last valid index") {
            _ = try CodexRemoteIndex.parse(data: data(["thread-project-membership-host-ids": []]))
        }
        rejects("oversized metadata is rejected before decoding") {
            _ = try CodexRemoteIndex.parse(data: Data(repeating: 32, count: CodexRemoteIndex.maximumBytes + 1))
        }

        var many: [String: String] = [:]
        var named: [[String: String]] = []
        for h in 0..<10 {
            for n in 0..<40 { many[uuid(h * 100 + n)] = "host-\(h)" }
            if h < 8 { named.append(["hostId": "host-\(h)", "displayName": "Machine \(h)"]) }
        }
        let capped = try CodexRemoteIndex.parse(data: data([
            "thread-project-membership-host-ids": many, "codex-managed-remote-connections": named]))
        let grouped = Dictionary(grouping: capped, by: \.hostID)
        expect(capped.count == 128 && grouped.count == 8, "discovery is bounded to 128 candidates and eight hosts")
        expect(Set(grouped.keys) == Set((0..<8).map { "host-\($0)" }), "configured named hosts are preferred at host capacity")
        expect(grouped.values.allSatisfy { $0.count == 16 }, "capacity is shared fairly across all eight hosts")
        expect(capped.map(\.threadID) == capped.map(\.threadID).sorted(by: >), "selected candidates are newest first")
        expect(capped.contains(where: { $0.threadID == uuid(739) }) && !capped.contains(where: { $0.threadID == uuid(700) }),
               "latest UUIDv7 candidates survive while older candidates yield at capacity")
        let oneHost = try CodexRemoteIndex.parse(data: data(["thread-project-membership-host-ids":
            Dictionary(uniqueKeysWithValues: (0..<40).map { (uuid($0), host) })]))
        expect(oneHost.count == 32 && oneHost.first?.threadID == uuid(39) && oneHost.last?.threadID == uuid(8),
               "each host is bounded to its newest 32 hints")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("virtual-workplace-remote-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("metadata.json")
        try data(fixture).write(to: file)
        let fromFile = try CodexRemoteIndex.read(at: file)
        expect(fromFile == candidates, "bounded regular-file reader matches the pure parser")
        let link = folder.appendingPathComponent("metadata-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        rejects("symlink metadata is rejected") { _ = try CodexRemoteIndex.read(at: link) }
        rejects("directory metadata is rejected") { _ = try CodexRemoteIndex.read(at: folder) }
        let fifo = folder.appendingPathComponent("metadata-fifo")
        guard mkfifo(fifo.path, 0o600) == 0 else { fatalError("temporary FIFO creation failed") }
        rejects("FIFO metadata is rejected without waiting for a writer") { _ = try CodexRemoteIndex.read(at: fifo) }
        rejects("missing metadata is rejected for caller cache handling") { _ = try CodexRemoteIndex.read(at: folder.appendingPathComponent("missing")) }
        let descriptor = Darwin.open(file.path, O_WRONLY)
        guard descriptor >= 0 else { fatalError("temporary fixture open failed") }
        defer { Darwin.close(descriptor) }
        guard ftruncate(descriptor, off_t(CodexRemoteIndex.maximumBytes + 1)) == 0 else { fatalError("fixture truncate failed") }
        rejects("oversized file is rejected from fstat") { _ = try CodexRemoteIndex.read(at: file) }
        print("PASS: \(checks) bounded remote candidate index checks (fixture-only; no live Codex reads)")
    }
}
