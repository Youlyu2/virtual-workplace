import Foundation
import Darwin

/// A real worker loop against synthetic IPC and metadata, with a hard footprint
/// guard. The main run loop drains its own pool so only worker retention counts.
@main
enum CodexObserverMemoryTests {
    private struct Failure: Error { var message: String }
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return info.phys_footprint
    }

    static func main() throws {
        signal(SIGPIPE, SIG_IGN)
        let measureOnly = CommandLine.arguments.contains("--measure-only")
        let home = URL(fileURLWithPath: "/tmp/vwm-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let peer = Process(), input = Pipe(), output = Pipe()
        peer.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        peer.arguments = ["python3", "Tests/CodexMemoryFixture.py", home.path]
        peer.standardInput = input; peer.standardOutput = output
        try peer.run()
        defer { try? input.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8)); peer.waitUntilExit() }
        let ready = output.fileHandleForReading.readData(ofLength: 6)
        precondition(ready == Data("ready\n".utf8), "isolated peer starts")
        let oldHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_HOME", home.path, 1)
        defer { if let oldHome { setenv("CODEX_HOME", oldHome, 1) } else { unsetenv("CODEX_HOME") } }
        let observer = CodexDesktopObserver()
        let start = ProcessInfo.processInfo.systemUptime
        var observedLocal = false
        var sequences: Set<Int> = []
        var latestSequence = 0
        var lastChangeAt = start
        observer.onUpdate = { result in
            observedLocal = observedLocal || result.sessions.contains { $0.hostID == "local" && $0.runtimeType == "active" }
            if let text = result.sessions.first(where: { $0.hostID == "local" })?.executionDetails?.latestUpdate,
               text.hasPrefix("fixture-sequence:"), let sequence = Int(text.dropFirst("fixture-sequence:".count)),
               sequences.insert(sequence).inserted {
                latestSequence = sequence
                lastChangeAt = ProcessInfo.processInfo.systemUptime
            }
        }
        observer.start()
        defer { observer.stop(); RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        var samples: [UInt64] = []
        var nextSample = 0.0
        while ProcessInfo.processInfo.systemUptime - start < 30 {
            autoreleasepool { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let bytes = footprint()
            if bytes > 768 * 1024 * 1024 {
                throw Failure(message: "footprint guard exceeded 768 MiB; stopping isolated worker")
            }
            if elapsed >= nextSample {
                print(String(format: "memory t=%.1fs footprint=%.1fMiB", elapsed, Double(bytes) / 1_048_576))
                fflush(stdout)
                if elapsed >= 6 { samples.append(bytes) }
                nextSample += 3
            }
        }
        try input.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8))
        peer.waitUntilExit()
        let summary = try JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent("memory-summary.json"))) as? [String: Any]
        guard observedLocal, samples.count >= 6, sequences.count >= 15, latestSequence >= 25,
              ProcessInfo.processInfo.systemUptime - lastChangeAt < 4,
              (summary?["markerDiscoveries"] as? Int ?? 0) >= 4 else {
            throw Failure(message: "observer must keep reading new rollout events and rescanning changing remote metadata until the test ends")
        }
        print("PASS: \(sequences.count) changing rollout updates through sequence \(latestSequence), \(summary?["markerDiscoveries"] as? Int ?? 0) changing remote candidates discovered")
        let growth = Int64(samples.last!) - Int64(samples.first!)
        let limit: Int64 = 16 * 1024 * 1024
        print(String(format: "%@: worker growth after warm-up %.1fMiB (limit 16MiB)", growth <= limit ? "PASS" : "FAIL", Double(growth) / 1_048_576))
        if growth > limit && !measureOnly { throw Failure(message: "observer footprint keeps growing") }
    }
}
