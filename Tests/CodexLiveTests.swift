import Foundation

@main
struct CodexLiveTests {
    private static var checks = 0

    private static func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(description)") }
    }

    private static func session(_ id: String, runtime: String = "active", flags: [String] = [],
                                turn: String? = nil, pending: Bool = false, title: String? = nil) -> CodexObservedSession {
        CodexObservedSession(id: id, title: title ?? "真实任务 \(id)", runtimeType: runtime,
                             activeFlags: flags, turnStatus: turn, pendingRequest: pending)
    }

    private static func feed(_ source: CodexLiveTaskSource, _ sessions: [CodexObservedSession],
                             at now: Date, connected: Bool = true, message: String = "本机 Codex 已连接") {
        source.applyObservation(CodexObservationResult(sessions: sessions, isConnected: connected, message: message), at: now)
    }

    static func main() throws {
        // Pure fixture observations only: never start the observer or read the
        // user's Codex metadata, socket, tasks, credentials or state snapshot.
        let now = Calendar.autoupdatingCurrent.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        var simulated = SceneSnapshot.empty(now: now)
        simulated.taskOrigin = .simulation
        simulated.mode = .standing
        simulated.preferredPosture = .standing
        simulated.tasks = [WorkplaceTask(id: "fake", title: "模拟中的假任务", status: .running, slot: 0, progress: 0.95)]
        simulated.completedToday = 27
        let source = CodexLiveTaskSource(snapshot: simulated)
        expect(source.snapshot.tasks.isEmpty, "restored simulation tasks cannot become real Codex tasks")
        expect(source.snapshot.completedToday == 0, "simulated completion totals cannot become real completion totals")
        expect(source.snapshot.taskOrigin == .codex && !source.isConnected, "real source starts explicitly offline")
        expect(source.snapshot.mode == .standing && source.snapshot.preferredPosture == .standing,
               "real source preserves the user's posture preference")

        source.setMode(.automatic, at: now)
        feed(source, [session("old", runtime: "idle", turn: "completed")], at: now)
        expect(source.snapshot.tasks.isEmpty && source.totalSessionCount == 0,
               "initial historical idle session is not displayed as current work")
        expect(source.snapshot.completedToday == 0, "historical completed turns do not inflate today's count")
        expect(source.isConnected && source.snapshot.resolvedActivity(at: now) != .offline,
               "an empty connected source is distinct from a disconnected source")

        var callbackCount = 0
        source.onChange = { callbackCount += 1 }
        feed(source, [session("a", title: "正在修复同步")], at: now.addingTimeInterval(1))
        expect(source.snapshot.tasks.count == 1 && source.snapshot.tasks[0].id == "a", "real identity reaches the scene")
        expect(source.snapshot.tasks[0].title == "正在修复同步" && source.snapshot.tasks[0].status == .running,
               "real title and active state replace placeholder task content")
        expect(source.snapshot.tasks[0].progress == nil && source.snapshot.tasks[0].startedAt == nil,
               "unknown progress and start time remain unknown")
        expect(source.snapshot.resolvedPose(at: now.addingTimeInterval(1)) == .standing,
               "automatic real work uses the remembered standing posture")
        expect(source.snapshot.resolvedActivity(at: now.addingTimeInterval(1)) == .working, "active observation drives working activity")
        let stableSlot = source.snapshot.tasks[0].slot

        let detailSource = CodexLiveTaskSource()
        var detailed = session("details")
        detailed.startedAt = now.addingTimeInterval(-45)
        detailed.executionDetails = CodexExecutionDetails(phase: .tool,
            latestUpdate: "检查真实任务详情", toolName: "mcp__cua_repl / js", updatedAt: now, turnID: "turn-1")
        feed(detailSource, [detailed], at: now)
        expect(detailSource.snapshot.tasks[0].executionDetails == detailed.executionDetails
               && detailSource.snapshot.tasks[0].startedAt == detailed.startedAt,
               "verified local event details and real turn start enrich the matching IPC task")
        expect(detailSource.snapshot.tasks[0].activityTitle == "调用工具"
               && detailSource.snapshot.tasks[0].currentStep?.contains("mcp__cua_repl / js") == true
               && detailSource.snapshot.tasks[0].progress == nil,
               "tool metadata changes the visible activity without inventing progress")
        detailed.activeFlags = ["waitingOnApproval"]
        feed(detailSource, [detailed], at: now)
        expect(detailSource.snapshot.tasks[0].activityTitle == "等待确认"
               && detailSource.snapshot.tasks[0].status == .waiting,
               "an approval wait takes priority over an emitted tool call")
        detailed.activeFlags = []
        detailed.runtimeType = "idle"
        feed(detailSource, [detailed], at: now)
        expect(detailSource.snapshot.tasks[0].executionDetails?.phase == .idle
               && detailSource.snapshot.tasks[0].executionDetails?.toolName == nil
               && detailSource.snapshot.completedToday == 0,
               "runtime idle clears the active tool without claiming success")
        detailed.runtimeType = "active"
        detailed.executionDetails?.phase = .idle
        feed(detailSource, [detailed], at: now)
        expect(detailSource.snapshot.tasks[0].executionDetails == nil && detailSource.snapshot.tasks[0].startedAt == nil,
               "old completed log metadata cannot decorate a newly active IPC turn")
        detailed.executionDetails?.phase = .thinking
        feed(detailSource, [detailed], at: now)
        feed(detailSource, [], at: now, connected: false)
        expect(detailSource.snapshot.tasks[0].executionDetails == nil && !detailSource.snapshot.isOnline,
               "disconnection removes active detail claims as well as stopping live animation")

        feed(source, [session("a", flags: ["waitingOnApproval"])], at: now.addingTimeInterval(2))
        expect(source.snapshot.tasks[0].status == .waiting && source.snapshot.tasks[0].slot == stableSlot,
               "approval waits retain screen identity while pausing work")
        expect(source.snapshot.resolvedActivity(at: now.addingTimeInterval(2)) == .waiting, "approval wait pauses typing")
        feed(source, [session("a", flags: ["waitingOnUserInput"])], at: now.addingTimeInterval(3))
        expect(source.snapshot.tasks[0].status == .waiting, "user-input flag is a real waiting state")
        feed(source, [session("a", pending: true)], at: now.addingTimeInterval(4))
        expect(source.snapshot.tasks[0].status == .waiting, "pending request alone prevents false active typing")

        feed(source, [session("a", runtime: "idle")], at: now.addingTimeInterval(5))
        expect(source.snapshot.tasks[0].status == .idle, "runtime idle is not guessed to be successful completion")
        expect(source.snapshot.completedToday == 0, "idle without a completion event does not count success")
        expect(source.snapshot.lastWorkEndedAt == now.addingTimeInterval(5), "idle begins the rest grace period")
        source.tick(at: now.addingTimeInterval(16))
        expect(source.snapshot.resolvedPose(at: now.addingTimeInterval(16)) == .slacking,
               "a finished real run eventually rests rather than typing forever")

        feed(source, [session("a")], at: now.addingTimeInterval(17))
        expect(source.snapshot.lastWorkEndedAt == nil && source.snapshot.tasks[0].slot == stableSlot,
               "resumed execution clears grace without moving its screen")
        feed(source, [session("a", runtime: "idle", turn: "completed")], at: now.addingTimeInterval(18))
        expect(source.snapshot.tasks[0].status == .completed && source.snapshot.completedToday == 1,
               "an explicit completed turn following active work counts once")
        feed(source, [session("a", runtime: "idle", turn: "completed")], at: now.addingTimeInterval(19))
        expect(source.snapshot.completedToday == 1, "duplicate observations cannot double-count completion")

        let delayed = CodexLiveTaskSource()
        feed(delayed, [session("delayed")], at: now)
        feed(delayed, [session("delayed", runtime: "idle")], at: now.addingTimeInterval(1))
        expect(delayed.snapshot.completedToday == 0 && delayed.snapshot.tasks[0].status == .idle,
               "unknown idle state waits for explicit completion evidence")
        feed(delayed, [session("delayed", runtime: "idle", turn: "completed")], at: now.addingTimeInterval(2))
        expect(delayed.snapshot.completedToday == 1 && delayed.snapshot.tasks[0].status == .completed,
               "delayed explicit completion still counts a previously observed active run")
        feed(delayed, [session("delayed", runtime: "idle", turn: "completed")], at: now.addingTimeInterval(3))
        expect(delayed.snapshot.completedToday == 1,
               "repeated delayed confirmation cannot count the same active run twice")

        feed(source, [session("a", runtime: "systemError")], at: now.addingTimeInterval(20))
        expect(source.snapshot.tasks[0].status == .failed, "runtime systemError remains a real failure")
        expect(source.snapshot.completedToday == 1 && source.snapshot.resolvedActivity(at: now.addingTimeInterval(20)) == .waiting,
               "failure waits for attention and never counts success")
        feed(source, [session("a", runtime: "idle", turn: "failed")], at: now.addingTimeInterval(21))
        expect(source.snapshot.tasks[0].status == .failed, "an idle runtime cannot hide an explicit failed turn")

        feed(source, [], at: now.addingTimeInterval(22), connected: false, message: "Codex 已断开")
        expect(!source.isConnected && !source.snapshot.isOnline && source.connectionMessage == "Codex 已断开",
               "disconnection is visible instead of silently falling back to simulation")
        expect(source.snapshot.tasks.count == 1 && source.snapshot.resolvedActivity(at: now.addingTimeInterval(22)) == .offline,
               "last known task is retained offline without pretending it still works")
        source.tick(at: now.addingTimeInterval(23))
        expect(!source.snapshot.isOnline, "heartbeat cannot turn a disconnected source back online")
        feed(source, [session("a", title: "恢复后的真实标题")], at: now.addingTimeInterval(24))
        expect(source.isConnected && source.snapshot.tasks[0].title == "恢复后的真实标题" && source.snapshot.tasks[0].status == .running,
               "reconnection refreshes real title and execution state")

        source.setMode(.slacking, at: now.addingTimeInterval(25))
        expect(source.snapshot.resolvedPose(at: now.addingTimeInterval(25)) == .slacking,
               "manual rest overrides a real active task")
        expect(source.snapshot.tasks[0].status == .running, "manual pose never rewrites the real task state")
        source.setMode(.sitting, at: now.addingTimeInterval(26))
        source.setMode(.automatic, at: now.addingTimeInterval(27))
        expect(source.snapshot.resolvedPose(at: now.addingTimeInterval(27)) == .sitting,
               "switching automatic back on uses the latest manual working posture")
        expect(callbackCount >= 10, "source changes notify the production view callback")

        let many = CodexLiveTaskSource()
        let initial = (0..<6).map { session("task-\($0)") }
        feed(many, initial, at: now)
        let originalSlots = Dictionary(uniqueKeysWithValues: many.snapshot.tasks.map { ($0.id, $0.slot) })
        feed(many, Array(initial.reversed()), at: now.addingTimeInterval(1))
        expect(Dictionary(uniqueKeysWithValues: many.snapshot.tasks.map { ($0.id, $0.slot) }) == originalSlots,
               "upstream ordering changes do not shuffle monitor identities")
        let replacement = initial.filter { $0.id != "task-1" } + [session("replacement")]
        feed(many, replacement, at: now.addingTimeInterval(2))
        expect(many.snapshot.tasks.first(where: { $0.id == "replacement" })?.slot == originalSlots["task-1"],
               "a new session reuses the vacant monitor instead of displacing retained sessions")
        expect(many.snapshot.tasks.filter { $0.id != "replacement" }.allSatisfy { originalSlots[$0.id] == $0.slot },
               "removing one real session preserves all other monitor positions")

        let idleRows = replacement.map { session($0.id, runtime: "idle") }
        feed(many, idleRows, at: now.addingTimeInterval(3))
        let overflow = idleRows + [session("new-running-1"), session("new-running-2")]
        feed(many, overflow, at: now.addingTimeInterval(4))
        expect(many.totalSessionCount == 8 && many.snapshot.totalSessionCount == 8 && many.snapshot.tasks.count == 6,
               "more than six sessions retain the true total while bounding scene screens")
        expect(many.snapshot.tasks.contains(where: { $0.id == "new-running-1" }) && many.snapshot.tasks.contains(where: { $0.id == "new-running-2" }),
               "new active work takes priority over retained idle screens at capacity")
        expect(Set(many.snapshot.tasks.map(\.slot)).count == 6 && many.snapshot.tasks.allSatisfy { (0..<6).contains($0.slot) },
               "overflow projection keeps unique legal monitor slots")

        let multiHost = CodexLiveTaskSource()
        let sameID = "01a189d1-145a-7673-9f28-8185b2c679a7"
        let localTwin = session(sameID, title: "本机同标识任务")
        var remoteTwin = session(sameID, title: "开发机原始标题")
        remoteTwin.hostID = "remote-ssh-codex-managed:DevBox%20Pro"
        remoteTwin.hostName = "DevBox Pro"
        remoteTwin.executionDetails = CodexExecutionDetails(phase: .tool, latestUpdate: "远端可见进展",
            toolName: "terminal", updatedAt: now, turnID: "remote-turn")
        remoteTwin.startedAt = now.addingTimeInterval(-20)
        feed(multiHost, [localTwin, remoteTwin], at: now)
        expect(multiHost.snapshot.tasks.count == 2 && Set(multiHost.snapshot.tasks.map(\.id)).count == 2,
               "the same UUID on two hosts creates independent screens")
        let remoteKey = remoteTwin.identity
        let remoteTask = multiHost.snapshot.tasks.first { $0.id == remoteKey }!
        expect(remoteKey != sameID && remoteKey.utf8.count <= 128 && remoteTask.sourceLabel == "DevBox Pro",
               "remote identity is stable, bounded and keeps its source label")
        expect(remoteTask.title == "开发机原始标题" && remoteTask.executionDetails == remoteTwin.executionDetails,
               "remote public details enrich their own task without rewriting its title")
        expect(multiHost.snapshot.tasks.first { $0.id == sameID }?.executionDetails == nil,
               "remote tool details never leak into a local task with the same UUID")
        let localSlot = multiHost.snapshot.tasks.first { $0.id == sameID }!.slot
        remoteTwin.runtimeType = "idle"; remoteTwin.turnStatus = "completed"
        feed(multiHost, [localTwin, remoteTwin], at: now.addingTimeInterval(1))
        expect(multiHost.snapshot.completedToday == 1
               && multiHost.snapshot.tasks.first { $0.id == remoteKey }?.status == .completed,
               "a verified remote completion counts once independently of local work")
        feed(multiHost, [localTwin], at: now.addingTimeInterval(2))
        expect(multiHost.snapshot.tasks.count == 1 && multiHost.snapshot.tasks[0].status == .running
               && multiHost.snapshot.tasks[0].slot == localSlot && multiHost.snapshot.isOnline,
               "a disconnected remote subscription cannot freeze or move local work")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VirtualWorkplace-live-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("state.json"))
        try store.write(many.snapshot)
        let roundtrip = try store.read()
        expect(roundtrip == many.snapshot, "live overflow metadata and idle states survive saver snapshot roundtrip")
        feed(many, [], at: now.addingTimeInterval(5))
        expect(many.snapshot.tasks.isEmpty && many.totalSessionCount == 0, "closed real sessions remove only their own scene data")

        var restoredReal = source.snapshot
        restoredReal.taskOrigin = .codex
        let restoredSource = CodexLiveTaskSource(snapshot: restoredReal)
        expect(restoredSource.snapshot.tasks.isEmpty && !restoredSource.snapshot.isOnline,
               "restored real titles alone cannot resurrect stale running tasks")
        expect(restoredSource.snapshot.completedToday == restoredReal.completedToday,
               "verified real daily completion total survives source reconstruction")
        let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: now)!
        restoredSource.tick(at: tomorrow)
        expect(restoredSource.snapshot.completedToday == 0, "real completion total resets at local calendar day change")
        print("PASS: \(checks) read-only Codex projection and persistence checks (no live observer started)")
    }
}
