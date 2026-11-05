import Foundation

@main
struct CodexDetailTests {
    private static var checks = 0
    private static let threadID = "11111111-2222-3333-4444-555555555555"
    private static let otherID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    private static let timestamp = "2026-10-29T20:00:00.000Z"
    private static let epoch: TimeInterval = 1_793_304_000

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }

    private static func data(_ object: [String: Any], newline: Bool = true) -> Data {
        var result = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if newline { result.append(0x0a) }
        return result
    }

    private static func event(_ type: String, _ payload: [String: Any], timestamp: String = timestamp) -> Data {
        data(["timestamp": timestamp, "type": type, "payload": payload])
    }

    private static func header(_ id: String = threadID, padding: Int = 0) -> Data {
        event("session_meta", ["id": id, "base_instructions": String(repeating: "x", count: padding)])
    }

    private static func started(_ turn: String, at value: TimeInterval = epoch) -> Data {
        event("event_msg", ["type": "task_started", "turn_id": turn, "root_turn_id": turn,
                             "started_at": value, "turn_attribution": ["turn_id": turn]])
    }

    private static func message(_ text: String, turn: String = "turn-one", phase: String = "commentary",
                                role: String = "assistant") -> Data {
        event("response_item", ["type": "message", "role": role, "phase": phase,
                                 "content": [["type": "output_text", "text": text]],
                                 "internal_chat_message_metadata_passthrough": ["turn_id": turn]])
    }

    private static func call(_ id: String, turn: String = "turn-one", name: String = "js",
                             namespace: String? = "mcp__cua_repl", custom: Bool = false) -> Data {
        var payload: [String: Any] = ["type": custom ? "custom_tool_call" : "function_call",
                                     "call_id": id, "name": name, "status": "completed",
                                     "internal_chat_message_metadata_passthrough": ["turn_id": turn]]
        if let namespace { payload["namespace"] = namespace }
        payload[custom ? "input" : "arguments"] = "DO_NOT_DISPLAY_ARGUMENT_SECRET"
        return event("response_item", payload)
    }

    private static func output(_ id: String, turn: String = "turn-one", custom: Bool = false) -> Data {
        event("response_item", ["type": custom ? "custom_tool_call_output" : "function_call_output",
                                 "call_id": id, "output": "DO_NOT_DISPLAY_OUTPUT_SECRET",
                                 "internal_chat_message_metadata_passthrough": ["turn_id": turn]])
    }

    private static func completed(_ turn: String, lastMessage: String? = nil) -> Data {
        var payload: [String: Any] = ["type": "task_complete", "turn_id": turn, "root_turn_id": turn,
                                      "started_at": epoch, "completed_at": epoch + 30]
        if let lastMessage { payload["last_agent_message"] = lastMessage }
        return event("event_msg", payload)
    }

    private static func accumulator() -> CodexRolloutAccumulator {
        var accumulator = CodexRolloutAccumulator(threadID: threadID)
        accumulator.consume(line: header())
        accumulator.consume(line: started("turn-one"))
        return accumulator
    }

    static func main() throws {
        var stream = accumulator()
        expect(stream.observation.startedAt == Date(timeIntervalSince1970: epoch), "task_started preserves an actual seconds-based start time")
        expect(stream.observation.details?.turnID == "turn-one", "execution metadata is tied to the actual turn")
        stream.consume(line: message("USER_SECRET", role: "user"))
        expect(stream.observation.startedAt == Date(timeIntervalSince1970: epoch),
               "a same-turn prompt after task_started preserves the verified turn clock")
        var newPrompt = accumulator()
        newPrompt.consume(line: message("NEW_USER_SECRET", turn: "turn-two", role: "user"))
        expect(newPrompt.observation.startedAt == nil && newPrompt.observation.details?.turnID == "turn-two",
               "a new prompt with no matching start cannot inherit the previous turn clock")
        stream.consume(line: message("已完成页面检查，正在修复安装入口。"))
        expect(stream.observation.details?.latestUpdate == "已完成页面检查，正在修复安装入口。", "visible assistant commentary becomes the recent update")
        let visible = stream.observation.details?.latestUpdate
        stream.consume(line: event("response_item", ["type": "reasoning", "summary": [["type": "summary_text", "text": "HIDDEN_REASONING_SECRET"]], "encrypted_content": "ENCRYPTED_SECRET", "internal_chat_message_metadata_passthrough": ["turn_id": "turn-one"]]))
        stream.consume(line: event("event_msg", ["type": "item_completed", "thread_id": threadID, "turn_id": "turn-one", "item": ["type": "Reasoning", "summary_text": ["HIDDEN_ITEM_SECRET"]]]))
        stream.consume(line: event("response_item", ["type": "agent_message", "content": [["type": "text", "text": "INTER_AGENT_SECRET"]]]))
        stream.consume(line: message("ANALYSIS_SECRET", phase: "analysis"))
        expect(stream.observation.details?.latestUpdate == visible, "reasoning, inter-agent communication and analysis never replace public commentary")
        var userOnly = accumulator()
        userOnly.consume(line: message("USER_SECRET", role: "user"))
        expect(userOnly.observation.details?.latestUpdate == nil, "a user prompt is not displayed as assistant progress")

        stream.consume(line: call("first"))
        expect(stream.observation.details?.phase == .tool, "a call with completed emission status is still an active tool")
        expect(stream.observation.details?.toolName?.contains("js") == true, "a tool label includes the public tool name")
        expect(stream.observation.details?.latestUpdate == visible, "tool arguments do not become the recent update")
        stream.consume(line: call("second", name: "exec", namespace: nil, custom: true))
        stream.consume(line: output("first"))
        expect(stream.observation.details?.phase == .tool && stream.observation.details?.toolName?.contains("exec") == true,
               "finishing one parallel call keeps the other active")
        stream.consume(line: output("unknown"))
        expect(stream.observation.details?.phase == .tool, "an unmatched output cannot finish an active call")
        stream.consume(line: output("second", custom: true))
        expect(stream.observation.details?.phase != .tool && stream.observation.details?.toolName == nil,
               "matching custom output ends the remaining tool")
        expect(stream.observation.details?.latestUpdate == visible, "tool output is not displayed as assistant progress")
        let encoded = try JSONEncoder().encode(stream.observation.details)
        let encodedText = String(data: encoded, encoding: .utf8)!
        expect(!encodedText.contains("SECRET"), "shared detail fields contain no hidden text, arguments or tool results")

        stream.consume(line: started("turn-two", at: epoch + 40))
        expect(stream.observation.details?.turnID == "turn-two" && stream.observation.details?.latestUpdate == nil,
               "a new turn clears the prior turn's commentary")
        expect(stream.observation.startedAt == Date(timeIntervalSince1970: epoch + 40), "a new turn starts a new real timer")
        stream.consume(line: message("OLD_TURN_SECRET", turn: "turn-one"))
        stream.consume(line: call("late-old", turn: "turn-one"))
        stream.consume(line: completed("turn-one"))
        expect(stream.observation.details?.turnID == "turn-two" && stream.observation.details?.latestUpdate == nil
               && stream.observation.details?.phase != .tool, "late old-turn records cannot contaminate the current turn")
        stream.consume(line: message("最终可见结果", turn: "turn-two", phase: "final_answer"))
        stream.consume(line: call("new-call", turn: "turn-two"))
        stream.consume(line: completed("turn-two"))
        expect(stream.observation.details?.phase == .idle && stream.observation.details?.toolName == nil,
               "explicit current-turn completion clears active tools")
        expect(stream.observation.details?.latestUpdate == "最终可见结果", "completion retains the last explicit public response")
        let beforeMalformed = stream.observation
        stream.consume(line: Data("{broken-json".utf8))
        stream.consume(line: Data("[]".utf8))
        stream.consume(line: event("unsupported_record", ["type": "message", "text": "UNKNOWN_SECRET"]))
        expect(stream.observation == beforeMalformed, "malformed and unknown records preserve the last valid details")

        var milliseconds = CodexRolloutAccumulator(threadID: threadID)
        milliseconds.consume(line: started("milliseconds", at: epoch * 1000))
        expect(milliseconds.observation.startedAt == Date(timeIntervalSince1970: epoch), "millisecond timestamps normalize to the same date")
        var bounded = accumulator()
        bounded.consume(line: message(String(repeating: "内容", count: 400)))
        bounded.consume(line: call("long-label", name: String(repeating: "x", count: 250)))
        expect((bounded.observation.details?.latestUpdate?.count ?? 0) <= 320, "public commentary is bounded to the scene snapshot budget")
        expect((bounded.observation.details?.toolName?.count ?? 0) <= 120, "tool labels are bounded independently of arguments")
        expect(bounded.observation.details?.latestUpdate?.isEmpty == false, "bounding retains useful public text")

        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("CodexDetailsFixtures-" + UUID().uuidString)
        let sessions = temporary.appendingPathComponent("sessions/2026/10/29")
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let path = sessions.appendingPathComponent("rollout-\(threadID)_\(otherID).jsonl")
        var fixture = header(padding: 24_000) + started("turn-one") + message("初始可见进展")
        try fixture.write(to: path)
        let reader = CodexRolloutReader(home: temporary)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.latestUpdate == "初始可见进展", "a realistic long session header validates the exact full thread identity")
        expect(reader.read(threadID: otherID, at: path.path) == nil, "a filename suffix cannot create a duplicate child session")
        let outside = temporary.appendingPathComponent("outside.jsonl")
        try fixture.write(to: outside)
        expect(reader.read(threadID: threadID, at: outside.path) == nil, "details are read only from the configured sessions tree")
        let escapingLink = sessions.appendingPathComponent("outside-link.jsonl")
        try fm.createSymbolicLink(at: escapingLink, withDestinationURL: outside)
        expect(reader.read(threadID: threadID, at: escapingLink.path) == nil, "a symlink cannot escape the allowed session tree")

        var partial = message("追加消息完整后才可见")
        partial.removeLast()
        fixture.append(partial.prefix(partial.count / 2))
        try fixture.write(to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.latestUpdate == "初始可见进展", "an incomplete trailing line is held without overwriting valid text")
        fixture.append(partial.suffix(partial.count - partial.count / 2)); fixture.append(0x0a)
        try fixture.write(to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.latestUpdate == "追加消息完整后才可见", "completing a trailing JSON line publishes it once")
        expect(reader.read(threadID: threadID, at: path.path)?.details?.latestUpdate == "追加消息完整后才可见", "an unchanged file preserves the cached observation")
        fixture = header() + started("turn-three", at: epoch + 100) + message("截断后新一轮", turn: "turn-three")
        try fixture.write(to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.turnID == "turn-three", "file truncation resets parser state before reading new content")
        let replacement = sessions.appendingPathComponent("replacement.jsonl")
        try (header() + started("turn-four") + message("替换文件的新进展", turn: "turn-four")).write(to: replacement)
        try fm.removeItem(at: path); try fm.moveItem(at: replacement, to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.latestUpdate == "替换文件的新进展", "inode rotation reloads the new session file")
        reader.retain(threadIDs: [])
        expect(reader.read(threadID: threadID, at: path.path)?.details?.turnID == "turn-four", "evicted sessions can be read again from validated source")
        let largeHeader = sessions.appendingPathComponent("large-header.jsonl")
        try (header(padding: 300_000) + started("oversized-header")).write(to: largeHeader)
        expect(reader.read(threadID: threadID, at: largeHeader.path) == nil, "header validation has a finite read budget")
        fixture = header() + started("before-burst") + call("unfinished", turn: "before-burst")
        try fixture.write(to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.phase == .tool, "a baseline pending call is visible before a log burst")
        fixture.append(Data(repeating: 0x78, count: CodexRolloutReader.maximumLineBytes + 64))
        fixture.append(0x0a)
        try fixture.write(to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details == nil, "an oversized unknown gap discards stale calls and public text")
        fixture.append(started("after-burst")); fixture.append(message("恢复后的公开进展", turn: "after-burst"))
        try fixture.write(to: path)
        expect(reader.read(threadID: threadID, at: path.path)?.details?.latestUpdate == "恢复后的公开进展", "bounded reading recovers after the end of an oversized line")
        try (header(otherID) + started("wrong") + message("WRONG_THREAD_SECRET", turn: "wrong")).write(to: replacement)
        try fm.removeItem(at: path); try fm.moveItem(at: replacement, to: path)
        expect(reader.read(threadID: threadID, at: path.path) == nil, "rotation to another thread fails closed rather than retaining another session's text")

        let now = Date()
        var state = SceneSnapshot.empty(now: now)
        state.tasks = [WorkplaceTask(id: threadID, title: "真实会话", status: .running, slot: 0,
                                    executionDetails: CodexExecutionDetails(phase: .tool, latestUpdate: "检查接口", toolName: "mcp__cua_repl.js", updatedAt: now, turnID: "turn-one"))]
        let store = StateStore(url: temporary.appendingPathComponent("snapshot/state.json"))
        try store.write(state)
        let roundtrip = try store.read()
        expect(roundtrip == state, "detail metadata survives the app-to-screen-saver state roundtrip")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        var legacyTasks = legacy["tasks"] as! [[String: Any]]
        legacyTasks[0].removeValue(forKey: "executionDetails"); legacy["tasks"] = legacyTasks
        let old = try JSONDecoder().decode(SceneSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(old.tasks[0].executionDetails == nil && old.tasks[0].status == .running, "old snapshots remain compatible without execution details")
        for field in 0..<4 {
            var invalid = state
            switch field {
            case 0: invalid.tasks[0].executionDetails?.latestUpdate = String(repeating: "x", count: 321)
            case 1: invalid.tasks[0].executionDetails?.toolName = String(repeating: "x", count: 121)
            case 2: invalid.tasks[0].executionDetails?.turnID = ""
            default: invalid.tasks[0].executionDetails?.updatedAt = Date(timeIntervalSince1970: -1)
            }
            do { try store.write(invalid); fatalError("FAIL: invalid detail accepted") }
            catch { checks += 1 }
        }
        print("PASS: \(checks) Codex detail projection, bounded log reading, privacy and shared-state checks; fixture files only")
    }
}
