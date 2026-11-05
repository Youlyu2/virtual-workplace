import Foundation

@main
struct ModelTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(description)") }
    }
    static func rejects(_ description: String, _ body: () throws -> Void) {
        do { try body(); fatalError("FAIL: expected rejection: \(description)") }
        catch { checks += 1 }
    }
    static func main() throws {
        let now = Date()
        var state = SceneSnapshot.empty(now: now)
        expect(state.resolvedPose(at: now) == .slacking, "empty scene rests")
        state.tasks = [WorkplaceTask(id: "a", title: "任务 A", status: .running, slot: 0)]
        expect(state.resolvedPose(at: now) == .sitting, "running task sits by default")
        expect(state.resolvedActivity(at: now) == .working, "running task works")
        state.preferredPosture = .standing
        expect(state.resolvedPose(at: now) == .standing, "preferred standing is respected")
        state.tasks[0].status = .waiting
        expect(state.resolvedActivity(at: now) == .waiting, "waiting pauses typing")
        state.tasks.append(WorkplaceTask(id: "b", title: "任务 B", status: .running, slot: 1))
        expect(state.resolvedActivity(at: now) == .working, "running wins over waiting")
        state.mode = .slacking
        expect(state.resolvedPose(at: now) == .slacking, "manual slacking wins over running")
        expect(state.resolvedActivity(at: now) == .resting, "manual slacking stops typing")
        state.mode = .automatic
        state.tasks = []
        state.lastWorkEndedAt = now
        expect(state.resolvedPose(at: now.addingTimeInterval(9)) == .standing, "grace period preserves posture")
        state.updatedAt = now.addingTimeInterval(10)
        expect(state.resolvedPose(at: now.addingTimeInterval(10)) == .slacking, "rests after ten seconds")
        state.tasks = [WorkplaceTask(id: "a", title: "任务", status: .running, slot: 0)]
        state.updatedAt = now
        expect(state.resolvedActivity(at: now.addingTimeInterval(11)) == .offline, "stale producer goes offline")
        expect(state.resolvedPose(at: now.addingTimeInterval(11)) == .slacking, "stale producer cannot fake work")
        state.isOnline = false
        expect(state.resolvedActivity(at: now) == .offline, "explicit exit immediately goes offline")

        let simulator = TaskSimulator()
        for _ in 0..<8 { simulator.addTask() }
        expect(simulator.snapshot.tasks.count == 6, "six task maximum")
        let kept = simulator.snapshot.tasks[4]
        let removedID = simulator.snapshot.tasks[1].id
        simulator.removeTask(id: removedID)
        simulator.addTask()
        expect(simulator.snapshot.tasks.last?.slot == 1, "lowest vacant slot reused")
        expect(simulator.snapshot.tasks.contains(kept), "existing task identities and slots remain stable")
        simulator.setMode(.standing)
        simulator.setMode(.automatic)
        expect(simulator.snapshot.preferredPosture == .standing, "manual stand updates next automatic posture")
        for task in simulator.snapshot.tasks { simulator.setTaskStatus(id: task.id, status: .completed) }
        let ended = simulator.snapshot.lastWorkEndedAt
        expect(ended != nil, "all-completed starts grace timer")
        simulator.removeTask(id: simulator.snapshot.tasks[0].id)
        expect(simulator.snapshot.lastWorkEndedAt == ended, "closing completed task does not reset grace timer")

        simulator.setDemoRunning(true)
        let start = simulator.snapshot.updatedAt
        expect(simulator.snapshot.tasks.count == 1, "demo begins with one task")
        simulator.tick(at: start.addingTimeInterval(19))
        expect(simulator.snapshot.tasks.count == 6, "demo reaches six screens")
        simulator.tick(at: start.addingTimeInterval(25))
        expect(simulator.snapshot.resolvedPose(at: simulator.snapshot.updatedAt) == .standing, "demo stands")
        simulator.tick(at: start.addingTimeInterval(31))
        expect(simulator.snapshot.resolvedActivity(at: simulator.snapshot.updatedAt) == .waiting, "demo waits")
        simulator.tick(at: start.addingTimeInterval(37))
        expect(simulator.snapshot.tasks.allSatisfy { $0.status == .completed }, "demo completes tasks")
        simulator.tick(at: start.addingTimeInterval(59))
        expect(simulator.snapshot.tasks.isEmpty && simulator.snapshot.resolvedPose(at: simulator.snapshot.updatedAt) == .slacking, "demo removes screens and rests")
        simulator.tick(at: start.addingTimeInterval(61))
        expect(simulator.snapshot.tasks.count == 1, "demo repeats with a clean cycle")
        simulator.addTask()
        expect(!simulator.snapshot.demoRunning, "manual operation stops demo")
        let count = simulator.snapshot.tasks.count
        simulator.tick(at: start.addingTimeInterval(90))
        expect(simulator.snapshot.tasks.count == count, "disabled demo never creates tasks")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("state.json"))
        try store.write(simulator.snapshot)
        let loaded = try store.read()
        expect(loaded == simulator.snapshot, "atomic state roundtrip")
        var remoteState = simulator.snapshot
        remoteState.tasks[0].hostID = "remote-ssh-codex-managed:DevBox%20Pro"
        remoteState.tasks[0].hostName = "DevBox Pro"
        try store.write(remoteState)
        let remoteRoundtrip = try store.read()
        expect(remoteRoundtrip == remoteState && remoteRoundtrip.tasks[0].sourceLabel == "DevBox Pro",
               "remote host identity and source label survive app-to-saver persistence")
        expect(remoteRoundtrip.tasks[0].title == simulator.snapshot.tasks[0].title,
               "host presentation preserves the exact canonical task title")
        var unidentifiedRemote = remoteState.tasks[0]
        unidentifiedRemote.hostName = nil
        expect(unidentifiedRemote.sourceLabel == "开发机", "an unnamed remote host never claims to be local")
        var invalid = simulator.snapshot
        invalid.schemaVersion = 2
        rejects("schema version") { try store.write(invalid) }
        invalid = simulator.snapshot
        invalid.tasks.append(invalid.tasks[0])
        rejects("duplicate ID and slot") { try store.write(invalid) }
        invalid = simulator.snapshot
        invalid.tasks[0].slot = -1
        rejects("invalid slot") { try store.write(invalid) }
        try Data("{broken-json".utf8).write(to: store.url)
        rejects("corrupt file") { _ = try store.read() }
        try Data(repeating: 32, count: 131_073).write(to: store.url)
        rejects("oversized file") { _ = try store.read() }
        simulator.markOffline()
        expect(!simulator.snapshot.isOnline && !simulator.snapshot.demoRunning, "quit records offline")

        let live = TaskSimulator(snapshot: .empty(now: now))
        live.addTask(at: now)
        let liveID = live.snapshot.tasks[0].id
        expect(live.snapshot.tasks[0].startedAt == now, "new task records real start time")
        live.tick(at: now.addingTimeInterval(40))
        expect(live.snapshot.tasks[0].progress == 0.5, "running task advances deterministic simulated progress")
        expect(live.snapshot.tasks[0].currentStep == "检查模拟结果" && live.snapshot.tasks[0].nextStep == "整理任务输出", "progress publishes current and next steps")
        live.setTaskStatus(id: liveID, status: .waiting, at: now.addingTimeInterval(41))
        live.tick(at: now.addingTimeInterval(75))
        expect(live.snapshot.tasks[0].progress == 0.5, "waiting freezes progress")
        expect(live.snapshot.tasks[0].currentStep == "等待你确认", "waiting publishes useful current action")
        live.setTaskStatus(id: liveID, status: .failed, at: now.addingTimeInterval(76))
        expect(live.snapshot.tasks[0].nextStep == "检查会话并重新运行", "failed task publishes next action")
        live.setTaskStatus(id: liveID, status: .running, at: now.addingTimeInterval(77))
        live.tick(at: now.addingTimeInterval(500))
        expect(live.snapshot.tasks[0].progress == 0.95 && live.snapshot.tasks[0].status == .running, "simulation caps progress without inventing completion")
        live.setTaskStatus(id: liveID, status: .completed, at: now.addingTimeInterval(501))
        expect(live.snapshot.tasks[0].progress == 1 && live.snapshot.completedToday == 1, "completion reports one and counts event")
        live.setTaskStatus(id: liveID, status: .completed, at: now.addingTimeInterval(502))
        expect(live.snapshot.completedToday == 1, "repeated completed assignment is not a new completion")
        live.setTaskStatus(id: liveID, status: .running, at: now.addingTimeInterval(503))
        expect(live.snapshot.tasks[0].progress == 0 && live.snapshot.tasks[0].startedAt == now.addingTimeInterval(503), "reopening completed task restarts timing and progress")
        live.setTaskStatus(id: liveID, status: .completed, at: now.addingTimeInterval(504))
        expect(live.snapshot.completedToday == 2, "reopened task completion counts a new event")
        live.removeTask(id: liveID, at: now.addingTimeInterval(505))
        expect(live.snapshot.completedToday == 2, "closing completed session preserves today's total")
        let restored = TaskSimulator(snapshot: live.snapshot)
        expect(restored.snapshot.completedToday == 2, "daily summary survives producer restart")
        let nextDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: now)!
        restored.tick(at: nextDay)
        expect(restored.snapshot.completedToday == 0 && Calendar.autoupdatingCurrent.isDate(restored.snapshot.summaryDay!, inSameDayAs: nextDay), "crossing local calendar day clears summary")

        let demoSummary = TaskSimulator(snapshot: .empty(now: now))
        demoSummary.setDemoRunning(true, at: now)
        demoSummary.tick(at: now.addingTimeInterval(37))
        expect(demoSummary.snapshot.completedToday == 6, "demo's completion events use daily counter")
        demoSummary.tick(at: now.addingTimeInterval(97))
        expect(demoSummary.snapshot.completedToday == 12, "new demo loop preserves today's prior completions")

        // Remove every new key to represent the exact 0.1 snapshot wire format.
        var legacyState = SceneSnapshot.empty(now: now)
        legacyState.tasks = [WorkplaceTask(id: "legacy", title: "旧任务", status: .running, slot: 0)]
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyState)) as! [String: Any]
        legacyJSON.removeValue(forKey: "completedToday")
        legacyJSON.removeValue(forKey: "summaryDay")
        legacyJSON["tasks"] = [["id": "legacy", "title": "旧任务", "status": "running", "slot": 0]]
        try JSONSerialization.data(withJSONObject: legacyJSON).write(to: store.url)
        let old = try store.read()
        expect(old.schemaVersion == 1 && old.completedToday == nil && old.summaryDay == nil, "old snapshot decodes without new daily fields")
        expect(old.tasks[0].progress == nil && old.tasks[0].currentStep == nil && old.tasks[0].startedAt == nil, "old task fields remain unknown rather than fabricated")
        expect(old.tasks[0].hostID == nil && old.tasks[0].hostName == nil && old.tasks[0].sourceLabel == "本机",
               "older snapshots decode absent host metadata as local without migration")
        let oldSimulator = TaskSimulator(snapshot: old)
        oldSimulator.tick(at: now.addingTimeInterval(5))
        expect(oldSimulator.snapshot.tasks[0].progress == nil, "legacy timing cannot invent progress after tick")
        try store.write(oldSimulator.snapshot)
        let migrated = try store.read()
        expect(migrated == oldSimulator.snapshot, "migrated optional snapshot roundtrips")

        invalid = legacyState
        invalid.tasks[0].progress = -0.01
        rejects("negative progress") { try store.write(invalid) }
        invalid.tasks[0].progress = 1.01
        rejects("progress above one") { try store.write(invalid) }
        invalid.tasks[0].progress = .infinity
        rejects("nonfinite progress") { try store.write(invalid) }
        invalid = legacyState
        invalid.tasks[0].startedAt = Date(timeIntervalSince1970: -1)
        rejects("invalid task start time") { try store.write(invalid) }
        invalid = legacyState
        invalid.tasks[0].currentStep = String(repeating: "步", count: 161)
        rejects("oversized task step") { try store.write(invalid) }
        invalid = legacyState
        invalid.completedToday = -1
        rejects("negative daily completion counter") { try store.write(invalid) }
        invalid = legacyState
        invalid.tasks[0].hostID = String(repeating: "机", count: 86)
        rejects("host identifier bounded in UTF-8 bytes") { try store.write(invalid) }
        invalid = legacyState
        invalid.tasks[0].hostName = String(repeating: "机", count: 81)
        rejects("oversized host display name") { try store.write(invalid) }
        invalid = legacyState
        invalid.tasks[0].hostName = " \n "
        rejects("blank host display name") { try store.write(invalid) }
        print("PASS: \(checks) model, demo, and persistence checks")
    }
}
