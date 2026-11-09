import Foundation
import Darwin

/// Numeric-only integration host. It requires an explicit test marker and
/// never opens the application's default directory, UI, or task observers.
@main enum AgentControlFixtureHost {
    private static func footprint() -> UInt64 {
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
        guard CommandLine.arguments.count == 2 else { throw AgentPuppetError.invalid("测试宿主需要独立目录") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let marker = directory.appendingPathComponent(".agent-test-fixture")
        guard directory.lastPathComponent.hasPrefix("agent-cli-"),
              (try? String(contentsOf: marker, encoding: .utf8)) == "synthetic-avatar-only" else {
            throw AgentPuppetError.invalid("拒绝使用非测试目录")
        }
        let store = StateStore(url: directory.appendingPathComponent("state.json"))
        var snapshot = SceneSnapshot.empty()
        let inbox = AgentControlInbox(directory: directory)
        inbox.onChange = {
            snapshot.employeeControlMode = inbox.mode
            snapshot.agentTimeline = inbox.timeline
            snapshot.updatedAt = Date()
            do { try store.write(snapshot) }
            catch { preconditionFailure("isolated snapshot write failed: \(error)") }
        }
        try store.write(snapshot)
        inbox.poll()
        print("READY"); fflush(stdout)
        let start = ProcessInfo.processInfo.systemUptime
        let stop = directory.appendingPathComponent("stop")
        while ProcessInfo.processInfo.systemUptime - start < 12 && !FileManager.default.fileExists(atPath: stop.path) {
            autoreleasepool { inbox.poll() }
            precondition(footprint() < 128 * 1_048_576, "isolated CLI fixture exceeded128MiB")
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}
