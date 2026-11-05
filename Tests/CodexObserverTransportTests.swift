import Foundation
import Darwin

@main
enum CodexObserverTransportTests {
    private struct Failure: Error { var message: String }
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw Failure(message: message) }
    }
    static func main() {
        do { try run() }
        catch { print("FAIL: \(error)"); exit(1) }
    }
    private static func run() throws {
        let previousPipeSignal = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, previousPipeSignal) }
        let home = URL(fileURLWithPath: "/tmp/vwt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let peer = Process(), input = Pipe(), output = Pipe()
        peer.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        peer.arguments = ["python3", "Tests/CodexTransportFixture.py", home.path]
        peer.standardInput = input; peer.standardOutput = output
        try peer.run()
        defer { try? input.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8)); peer.waitUntilExit() }
        var ready = [UInt8](repeating: 0, count: 64)
        let readyCount = Darwin.read(output.fileHandleForReading.fileDescriptor, &ready, ready.count)
        try expect(readyCount == 6 && Data(ready.prefix(max(0, readyCount))) == Data("ready\n".utf8), "isolated IPC peer starts")
        let savedHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_HOME", home.path, 1)
        defer { if let savedHome { setenv("CODEX_HOME", savedHome, 1) } else { unsetenv("CODEX_HOME") } }
        let observer = CodexDesktopObserver(), source = CodexLiveTaskSource()
        var latest = CodexObservationResult(sessions: [], isConnected: false, message: "fixture starting")
        var connectedOnce = false, disconnectedAfterConnection = false
        observer.onUpdate = { result in
            if connectedOnce && !result.isConnected { disconnectedAfterConnection = true }
            connectedOnce = connectedOnce || result.isConnected
            latest = result; source.applyObservation(result, at: Date())
        }
        let keepAlive = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in }
        observer.start()
        defer { observer.stop(); RunLoop.current.run(until: Date().addingTimeInterval(0.2)); keepAlive.invalidate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 7
        func wait(_ message: String, _ condition: () -> Bool) throws {
            while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            try expect(condition(), message)
        }
        func command(_ value: String) throws { try input.fileHandleForWriting.write(contentsOf: Data("\(value)\n".utf8)) }
        let localID = "11111111-1111-7111-8111-111111111111"
        let remoteID = "22222222-2222-7222-8222-222222222222"
        let remoteHost = "remote-ssh-codex-managed:Fixture"
        let remoteKey = CodexThreadIdentity.key(threadID: remoteID, hostID: remoteHost)
        try wait("both hosts independently publish running tasks") { source.snapshot.tasks.count == 2 }
        let localSlot = source.snapshot.tasks.first { $0.id == localID }?.slot
        try expect(source.snapshot.tasks.allSatisfy { $0.status == .running }, "initial IPC runtime state reaches projection")
        try command("gap")
        try wait("remote revision gap clears only remote active claims") { latest.sessions.count == 1 && source.snapshot.tasks.count == 1 }
        try expect(latest.isConnected && source.snapshot.tasks.first?.id == localID && source.snapshot.tasks.first?.slot == localSlot,
                   "local task stays live and keeps its screen while remote resynchronizes")
        try command("fresh")
        try wait("fresh remote snapshot recovers despite queued old patches") { source.snapshot.tasks.contains { $0.id == remoteKey && $0.title == "Remote recovered" } }
        try expect(source.snapshot.tasks.first { $0.id == localID }?.slot == localSlot, "remote recovery preserves local monitor identity")
        try command("unload")
        try wait("remote notLoaded removes its projected monitor") { latest.sessions.contains { $0.hostID == remoteHost && $0.runtimeType == "notLoaded" } && source.snapshot.tasks.count == 1 }
        try command("fail")
        try wait("remote owner discovery failure removes only its subscription") { latest.sessions.count == 1 && latest.sessions.first?.hostID == "local" }
        try expect(!disconnectedAfterConnection && latest.isConnected && source.isConnected, "remote failures never disconnect the local source")
        try expect(source.snapshot.tasks.first?.id == localID && source.snapshot.tasks.first?.status == .running
                   && source.snapshot.tasks.first?.slot == localSlot, "local work remains running in its original slot after remote unload")
        try command("stop"); peer.waitUntilExit()
        let summary = try JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent("peer-summary.json"))) as? [String: Any]
        try expect(peer.terminationStatus == 0 && (summary?["remoteFollows"] as? Int ?? 0) >= 2, "remote recovery actually requested a new snapshot")
        try expect(Set(summary?["methods"] as? [String] ?? []) == Set(["initialize", "thread-owner-discovery", "thread-stream-following-changed"]),
                   "production observer uses only initialization and read-only subscriptions")
        print("PASS: \(checks) isolated Codex transport checks (five host lifecycle scenarios; no real files or IPC)")
    }
}
