import Foundation
import Darwin

@main enum AgentControlInboxTests {
    private static var checks = 0
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static var fileClock: TimeInterval = 1_900_000_000

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), "FAIL: \(message)")
    }
    private static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure("FAIL: expected rejection: \(message)") }
        catch { checks += 1 }
    }
    private static func temporary(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("agent-inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
    private static func object(_ file: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    }
    private static func write(_ command: [String: Any], to directory: URL, date: Date? = nil) throws {
        let file = directory.appendingPathComponent("agent-command.json")
        try JSONSerialization.data(withJSONObject: command, options: [.sortedKeys]).write(to: file, options: .atomic)
        fileClock += 1
        try FileManager.default.setAttributes([.modificationDate: date ?? Date(timeIntervalSince1970: fileClock),
                                               .posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private static func command(_ op: String, fields: [String: Any] = [:], id: String = UUID().uuidString,
                                issuedAt: Double = now.timeIntervalSince1970) -> [String: Any] {
        fields.merging(["id": id, "issuedAt": issuedAt, "op": op]) { _, new in new }
    }

    static func main() throws {
        try temporary { directory in
            let inbox = AgentControlInbox(directory: directory)
            expect(inbox.mode == .automatic && inbox.timeline == nil, "new inbox leaves the original controller in charge")
            rejects("poses require explicit Agent ownership") { _ = try inbox.apply(["op": "pose", "pose": [:]], at: now) }
            var changes = 0; inbox.onChange = { changes += 1 }
            _ = try inbox.apply(["op": "mode", "mode": "agent"], at: now)
            expect(inbox.mode == .agent && inbox.timeline?.sample(at: now) == .neutral && changes == 1,
                   "takeover starts from a finite neutral pose")
            _ = try inbox.apply(["op": "pose", "duration": 1.0,
                "pose": ["facing": "front", "joints": ["leftShoulder": -37.125, "rightElbow": 24.75],
                         "face": ["eyes": 0.375, "mouth": 0.8125]]], at: now)
            let end = inbox.timeline!.sample(at: now.addingTimeInterval(2))
            expect(end.angle(.leftShoulder) == -37.125 && end.angle(.rightElbow) == 24.75
                   && end.face.eyes == 0.375 && end.face.mouth == 0.8125 && end.facing == .front,
                   "local commands preserve arbitrary joint and expression targets")
            _ = try inbox.apply(["op": "pose", "pose": ["face": ["brows": -0.44]]], at: now.addingTimeInterval(2))
            let partial = inbox.timeline!.sample(at: now.addingTimeInterval(4))
            expect(partial.face.brows == -0.44 && partial.face.mouth == end.face.mouth
                   && partial.joints == end.joints, "partial updates preserve unspecified current joint and face targets")
            let saved = inbox.timeline
            _ = try inbox.apply(["op": "mode", "mode": "automatic"], at: now.addingTimeInterval(4))
            expect(inbox.mode == .automatic && inbox.timeline == saved, "release preserves the last pose without leaving Agent in control")
            rejects("release prevents subsequent pose control") { _ = try inbox.apply(["op": "pose", "pose": [:]], at: now) }
            _ = try inbox.apply(["op": "mode", "mode": "agent"], at: now.addingTimeInterval(4))
            expect(inbox.timeline == saved, "taking over again retains the existing finite trajectory")
            let status = inbox.status(at: now.addingTimeInterval(4))
            let capabilities = status["capabilities"] as! [String: Any]
            expect((capabilities["jointLimits"] as! [String: Any]).count == 12,
                   "status describes every numeric joint limit")
            expect(status["tasks"] == nil && status["pendingNotes"] == nil && status["statePath"] == nil,
                   "avatar status does not expose personal tasks, notes or state paths")
            for bad in ["not-an-op", "launch", "execute"] {
                rejects("unknown operations cannot become arbitrary execution") { _ = try inbox.apply(["op": bad], at: now) }
            }
            for mode: Any in ["model-api", "AGENT", true, NSNull()] {
                rejects("unknown mode values reject") { _ = try inbox.apply(["op": "mode", "mode": mode], at: now) }
            }
        }

        try temporary { directory in
            let inbox = AgentControlInbox(directory: directory, mode: .agent)
            let patches: [[String: Any]] = [
                ["angle": 3], ["x": true], ["y": "270"], ["x": NSNull()], ["facing": 1], ["facing": "diagonal"],
                ["x": 459.9], ["y": 311.0], ["x": Double.nan],
                ["joints": ["imaginary": 3]], ["joints": ["leftShoulder": true]],
                ["joints": ["rightElbow": 156]], ["joints": []],
                ["face": ["smile": 1]], ["face": ["mouth": true]],
                ["face": ["eyes": -0.1]], ["face": ["mouthOpen": Double.infinity]], ["face": "happy"]
            ]
            for patch in patches {
                let saved = inbox.timeline
                rejects("invalid patch rejects atomically") { _ = try inbox.apply(["op": "pose", "pose": patch], at: now) }
                expect(inbox.timeline == saved, "rejected patches never mutate the current trajectory")
            }
            for duration: Any in [0, -1, 15.001, Double.nan, Double.infinity, true, "fast", NSNull()] {
                rejects("explicit duration must be a finite number in range") {
                    _ = try inbox.apply(["op": "pose", "duration": duration, "pose": ["face": ["mouth": 0.5]]], at: now)
                }
            }
            _ = try inbox.apply(["op": "pose", "duration": 0.01,
                                "pose": ["joints": ["leftShoulder": 165]]], at: now)
            expect(inbox.timeline!.duration >= 165 / 360, "short transitions extend to respect the joint speed limit")
            for index in 0..<1000 {
                _ = try inbox.apply(["op": "pose", "duration": 1.0,
                    "pose": ["joints": ["leftShoulder": Double(index % 100)]]], at: now)
                expect(inbox.timeline!.frames.count == 2, "rapid commands replace a bounded trajectory rather than append a queue")
            }
            expect(inbox.timeline!.frames.last!.pose.angle(.leftShoulder) == 99,
                   "the latest rapid command owns the target")
            let timelineBytes = try JSONEncoder().encode(inbox.timeline!)
            expect(timelineBytes.count < 4096, "repeated replacements do not grow the snapshot payload")
        }

        try temporary { directory in
            let inbox = AgentControlInbox(directory: directory, mode: .agent)
            _ = try inbox.apply(["op": "sequence", "frames": [
                ["time": 1.0, "pose": ["joints": ["leftShoulder": -45.125]]],
                ["time": 2.0, "pose": ["face": ["mouthOpen": 0.42]]]
            ]], at: now)
            expect(inbox.timeline!.frames.count == 3 && inbox.timeline!.frames.last!.pose.angle(.leftShoulder) == -45.125
                   && inbox.timeline!.frames.last!.pose.face.mouthOpen == 0.42,
                   "arbitrary sequence frames accumulate sparse targets into complete poses")
            let original = inbox.timeline
            let invalidSequences: [[[String: Any]]] = [[],
                [["time": 0, "pose": [:]]], [["time": -1, "pose": [:]]],
                [["time": true, "pose": [:]]], [["time": "1", "pose": [:]]],
                [["time": 1, "pose": [:]], ["time": 0.5, "pose": [:]]],
                [["time": 1, "pose": [:]], ["time": 16, "pose": [:]]],
                [["time": 1, "pose": [:]], ["time": 2, "pose": ["joints": ["leftKnee": 131]]]]]
            for frames in invalidSequences {
                rejects("invalid sequence rejects atomically") { _ = try inbox.apply(["op": "sequence", "frames": frames], at: now) }
                expect(inbox.timeline == original, "a bad later keyframe cannot partially replace the previous trajectory")
            }
            let full = (1...31).map { ["time": Double($0) / 3, "pose": [:]] as [String: Any] }
            _ = try inbox.apply(["op": "sequence", "frames": full], at: now)
            expect(inbox.timeline!.frames.count == 32, "31 submitted targets plus the current pose fit the bounded timeline")
            rejects("32 submitted targets exceed the trajectory cap") {
                _ = try inbox.apply(["op": "sequence", "frames": full + [["time": 11, "pose": [:]]]], at: now)
            }
        }

        try temporary { directory in
            let inbox = AgentControlInbox(directory: directory)
            inbox.poll(at: now)
            expect(inbox.mode == .automatic && inbox.lastError == nil, "missing mailbox leaves control unchanged and publishes status")
            let statusURL = directory.appendingPathComponent("agent-status.json")
            let permissions = try FileManager.default.attributesOfItem(atPath: statusURL.path)[.posixPermissions] as! NSNumber
            expect(permissions.intValue & 0o777 == 0o600, "local status is user-readable only")
            try write(command("mode", fields: ["mode": "agent"]), to: directory)
            inbox.poll(at: now)
            let successfulResult = try object(directory.appendingPathComponent("agent-result.json"))
            expect(inbox.mode == .agent && successfulResult["ok"] as? Bool == true,
                   "a fresh mailbox command receives a matching successful result")
            for age in [15.001, -2.001] {
                try write(command("mode", fields: ["mode": "automatic"], issuedAt: now.timeIntervalSince1970 - age), to: directory)
                inbox.poll(at: now)
                let result = try object(directory.appendingPathComponent("agent-result.json"))
                expect(result["ok"] as? Bool == false && inbox.mode == .agent && inbox.lastError != nil,
                       "stale and too-far-future commands receive a rejection without taking ownership")
            }
            let idA = UUID().uuidString, idB = UUID().uuidString
            let a = command("pose", fields: ["pose": ["joints": ["headTilt": 12.5]]], id: idA)
            let b = command("pose", fields: ["pose": ["joints": ["headTilt": -21.5]]], id: idB)
            try write(a, to: directory); inbox.poll(at: now)
            let recovered = try object(directory.appendingPathComponent("agent-result.json"))
            expect(recovered["ok"] as? Bool == true
                   && (recovered["result"] as? [String: Any])?["error"] as? String == "",
                   "a successful pose after a rejected command does not repeat the old error")
            try write(b, to: directory); inbox.poll(at: now)
            let latest = inbox.timeline
            try write(a, to: directory); inbox.poll(at: now)
            expect(inbox.timeline == latest, "recent nonconsecutive UUID replays do not re-execute old commands")
            let restarted = AgentControlInbox(directory: directory, mode: .agent, timeline: latest)
            let persisted = restarted.timeline
            restarted.poll(at: now)
            expect(restarted.timeline == persisted, "a restored inbox does not replay the last acknowledged command")
            let stamp = Date(timeIntervalSince1970: fileClock + 100)
            try write(command("pose", fields: ["pose": ["face": ["mouth": 0.1]]]), to: directory, date: stamp)
            inbox.poll(at: now)
            try write(command("pose", fields: ["pose": ["face": ["mouth": 0.9]]]), to: directory, date: stamp)
            inbox.poll(at: now)
            expect(inbox.timeline!.frames.last!.pose.face.mouth == 0.9,
                   "a new atomic command UUID is read even when its modification timestamp matches")
        }

        try temporary { directory in
            let input = directory.appendingPathComponent("agent-command.json")
            let target = directory.appendingPathComponent("outside.json")
            let payload = try JSONSerialization.data(withJSONObject: command("mode", fields: ["mode": "agent"]))
            try payload.write(to: target)
            try FileManager.default.createSymbolicLink(at: input, withDestinationURL: target)
            let inbox = AgentControlInbox(directory: directory)
            inbox.poll(at: now)
            expect(inbox.mode == .automatic && inbox.lastError != nil, "symlink inputs are rejected")
            let untouched = try Data(contentsOf: target)
            expect(untouched == payload, "reading a symlink cannot modify its target")
        }
        try temporary { directory in
            let input = directory.appendingPathComponent("agent-command.json")
            try Data(repeating: 0x20, count: 65_537).write(to: input)
            let inbox = AgentControlInbox(directory: directory); inbox.poll(at: now)
            expect(inbox.mode == .automatic && inbox.lastError != nil, "oversized input is rejected before parsing")
        }
        try temporary { directory in
            let input = directory.appendingPathComponent("agent-command.json")
            precondition(mkfifo(input.path, 0o600) == 0)
            let inbox = AgentControlInbox(directory: directory)
            let began = ProcessInfo.processInfo.systemUptime; inbox.poll(at: now)
            expect(ProcessInfo.processInfo.systemUptime - began < 1 && inbox.lastError != nil,
                   "FIFO input is rejected without waiting for a writer")
        }
        for malformed in [Data("[]".utf8), Data("{".utf8), Data() ] {
            try temporary { directory in
                try malformed.write(to: directory.appendingPathComponent("agent-command.json"))
                let inbox = AgentControlInbox(directory: directory); inbox.poll(at: now)
                expect(inbox.mode == .automatic && inbox.lastError != nil, "malformed or empty input cannot change control")
            }
        }
        print("PASS: \(checks) local avatar protocol, replacement, replay and mailbox isolation checks")
    }
}
