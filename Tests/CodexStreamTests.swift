import Foundation

@main
struct CodexStreamTests {
    private static var count = 0
    private static let now = Date(timeIntervalSince1970: 1_793_392_400)
    private static let base: [Any] = ["turnHistory", "history", "entitiesByKey", "new"]
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; if !value() { fatalError("FAIL: \(message)") }
    }
    private static func message(_ text: String, phase: String = "commentary") -> [String: Any] {
        ["id": "message", "type": "agentMessage", "text": text, "phase": phase]
    }
    private static func tool(_ status: String = "inProgress", id: String = "tool") -> [String: Any] {
        ["id": id, "type": "dynamicToolCall", "namespace": "cua_repl", "tool": "js", "status": status,
         "arguments": ["secret": "ARGS_SECRET"], "contentItems": ["OUTPUT_SECRET"]]
    }
    private static func turn(_ id: String = "new-turn", status: String = "inProgress", items: [[String: Any]] = []) -> [String: Any] {
        ["turnId": id, "status": status, "turnStartedAtMs": now.timeIntervalSince1970 * 1000,
         "items": items, "params": ["input": "USER_SECRET"]]
    }
    private static func state(_ items: [[String: Any]] = []) -> [String: Any] {
        ["turns": [], "turnHistory": ["kind": "canonical", "history": [
            "generation": 2, "isComplete": true,
            "entitiesByKey": ["new": turn(items: items), "old": turn("old-turn", status: "completed", items: [message("OLD")])],
            "islands": [["id": "one", "entries": [["key": "old", "value": "old"], ["key": "new", "value": "new"]]]]
        ]]]
    }
    private static func patch(_ path: [Any], _ value: Any, op: String = "replace") -> [String: Any] {
        ["path": path, "value": value, "op": op]
    }
    static func main() throws {
        var reducer = CodexStreamDetails(state: state([message("  正在\n检查  页面 ")]), at: now)
        expect(reducer.turnStatus == "inProgress", "canonical latest status follows island order")
        expect(reducer.details?.turnID == "new-turn", "dictionary insertion order does not choose the turn")
        expect(reducer.startedAt == now, "milliseconds become an actual turn start")
        expect(reducer.details?.latestUpdate == "正在 检查 页面", "visible public message is flattened")
        expect(reducer.details?.phase == .working, "message-only active turn is working")
        reducer.apply(patch(base + ["items", 0, "text"], "已检查完成"), at: now.addingTimeInterval(1))
        expect(reducer.details?.latestUpdate == "已检查完成", "partial public text patch updates only visible text")
        reducer.apply(patch(base + ["items", 1], tool(), op: "add"), at: now)
        expect(reducer.details?.phase == .tool, "in-progress tool is active")
        expect(reducer.details?.toolName == "cua_repl / js", "only public tool identity is retained")
        reducer.apply(patch(base + ["items", 1, "status"], "completed"), at: now)
        expect(reducer.details?.phase == .working && reducer.details?.toolName == nil, "tool completion stops tool phase")
        reducer.apply(patch(base + ["items", 2], tool("inProgress", id: "two"), op: "add"), at: now)
        reducer.apply(patch(base + ["items", 3], tool("inProgress", id: "three"), op: "add"), at: now)
        expect(reducer.details?.toolName == "cua_repl / js (+1)", "parallel tools have a bounded count")
        reducer.apply(patch(base + ["completedItemIds", "two"], true, op: "add"), at: now)
        expect(reducer.details?.toolName == "cua_repl / js", "completion ID closes its matching active tool")
        reducer.apply(patch(base + ["items", 3], NSNull(), op: "remove"), at: now)
        expect(reducer.details?.toolName == nil, "item removal closes the remaining tool")
        reducer.apply(patch(base + ["items", 3], ["type": "reasoning", "id": "reason", "summary": ["HIDDEN"], "content": ["HIDDEN"]], op: "add"), at: now)
        expect(reducer.details?.phase == .thinking, "reasoning type supplies only a phase marker")
        expect(reducer.details?.latestUpdate == "已检查完成", "reasoning never replaces public commentary")
        reducer.apply(patch(base + ["completedItemIds", "reason"], true, op: "add"), at: now)
        expect(reducer.details?.phase == .working, "completed reasoning stops thinking phase")
        reducer.apply(patch(base + ["items", 4], message("ANALYSIS_SECRET", phase: "analysis"), op: "add"), at: now)
        expect(reducer.details?.latestUpdate == "已检查完成", "analysis-phase assistant strings are not read")
        reducer.apply(patch(base + ["items", 5], ["type": "userMessage", "text": "USER_SECRET", "content": ["USER_SECRET"]], op: "add"), at: now)
        expect(reducer.details?.latestUpdate == "已检查完成", "user messages are not progress")
        reducer.apply(patch(base + ["items", 1, "arguments"], "NEW_ARGUMENT_SECRET"), at: now)
        reducer.apply(patch(base + ["items", 3, "content", 0], "NEW_REASONING_SECRET"), at: now)
        expect(reducer.details?.latestUpdate == "已检查完成", "nested arguments and reasoning patches do not become text")
        reducer.apply(patch(base + ["status"], "completed"), at: now)
        expect(reducer.turnStatus == "completed" && reducer.details?.phase == .idle, "explicit turn completion stops active phases")
        reducer.apply(patch(base + ["items", 6], tool(), op: "add"), at: now)
        expect(reducer.details?.phase == .idle && reducer.details?.toolName == nil, "completed turn cannot display an old active tool")

        var compatibility = CodexStreamDetails(state: state([message("canonical progress"), tool()]), at: now)
        compatibility.apply(patch(["turns"], [] as [[String: Any]]), at: now)
        expect(compatibility.details?.turnID == "new-turn" && compatibility.details?.latestUpdate == "canonical progress", "empty compatibility turns patch cannot erase canonical details")
        expect(compatibility.startedAt == now && compatibility.details?.phase == .tool, "compatibility array keeps the current canonical clock and active tool")
        compatibility.apply(patch(base + ["items", 1, "status"], "completed"), at: now)
        expect(!compatibility.needsSnapshot && compatibility.details?.phase == .working, "canonical partial patches continue normally after compatibility array replacement")

        var newTurn = CodexStreamDetails(state: state([message("PREVIOUS")]), at: now)
        let newKey: [Any] = ["turnHistory", "history", "entitiesByKey", "next"]
        newTurn.apply(patch(newKey, turn("next-turn"), op: "add"), at: now)
        expect(newTurn.details?.turnID == "new-turn", "new entity is not current before ordered entry arrives")
        newTurn.apply(patch(["turnHistory", "history", "islands", 0, "entries", 2], ["key": "next", "value": "next"], op: "add"), at: now)
        expect(newTurn.details?.turnID == "next-turn", "new ordered entry selects a buffered entity")
        expect(newTurn.details?.latestUpdate == nil && newTurn.details?.toolName == nil, "new turn does not inherit progress or tool")
        expect(newTurn.startedAt == now, "new turn has its own clock")
        newTurn.apply(patch(newKey + ["items", 0], message("最新"), op: "add"), at: now)
        expect(newTurn.details?.latestUpdate == "最新", "new turn starts collecting its own public progress")
        newTurn.apply(patch(newKey + ["turnStartedAtMs"], NSNull(), op: "remove"), at: now)
        expect(newTurn.startedAt == nil, "missing start does not invent elapsed time")
        newTurn.apply(patch(newKey + ["items", 0, "phase"], "analysis"), at: now)
        expect(newTurn.details?.latestUpdate == nil, "phase change removes no-longer-public text")
        newTurn.apply(patch(newKey + ["items", 0, "type"], "userMessage"), at: now)
        expect(newTurn.needsSnapshot && newTurn.details == nil && newTurn.turnStatus == nil, "unknown item structure fails closed and requests a snapshot")
        newTurn.apply(patch(newKey + ["status"], "inProgress"), at: now)
        expect(newTurn.details == nil, "invalid reducer cannot revive stale state from a later partial patch")

        let long = String(repeating: "甲", count: 900)
        let bounded = CodexStreamDetails(state: state([message(long), ["type": "dynamicToolCall", "status": "inProgress", "namespace": "safe\n", "tool": String(repeating: "t", count: 500)]]), at: now)
        expect(bounded.details?.latestUpdate?.count == 320, "progress text has the shared 320-character bound")
        expect((bounded.details?.toolName?.count ?? 999) <= 120, "tool names have the shared 120-character bound")
        expect(bounded.details?.toolName?.contains("\n") == false, "tool names strip control characters")
        let data = try JSONEncoder().encode(bounded.details)
        let encoded = String(decoding: data, as: UTF8.self)
        expect(!encoded.contains("ARGS_SECRET") && !encoded.contains("OUTPUT_SECRET"), "encoded projected details contain no private tool fields")

        var legacy = CodexStreamDetails(state: ["turns": [turn("old", status: "completed"), turn("latest", items: [message("legacy")])]], at: now)
        expect(legacy.details?.turnID == "latest" && legacy.details?.latestUpdate == "legacy", "legacy array uses the latest turn")
        legacy.apply(patch(["turns", 1, "items", 0, "text"], "new legacy"), at: now)
        expect(legacy.details?.latestUpdate == "new legacy", "legacy partial item patches work")
        legacy.apply(patch(["turns", 2], turn("appended"), op: "add"), at: now)
        expect(legacy.details?.turnID == "appended" && legacy.details?.latestUpdate == nil, "legacy append resets details")
        legacy.apply(patch(["turns", 2, "status"], "failed"), at: now)
        expect(legacy.turnStatus == "failed" && legacy.details?.phase == .idle, "legacy failure stops phase")
        legacy.apply(patch(["turns", 2], NSNull(), op: "remove"), at: now)
        expect(legacy.details?.turnID == "latest", "legacy remove restores indexed preceding turn")
        let unknown = CodexStreamDetails(state: ["turns": [turn(status: "newUnknownStatus")]], at: now)
        expect(unknown.turnStatus == nil && unknown.details == nil, "unknown turn statuses cannot invent activity")
        var command = CodexStreamDetails(state: state([["type": "commandExecution", "status": "inProgress", "command": "SECRET_COMMAND", "aggregatedOutput": "SECRET_OUTPUT"]]), at: now)
        expect(command.details?.toolName == "终端命令", "terminal execution uses a generic name")
        command.apply(patch(base + ["items", 0, "command"], "ANOTHER_SECRET"), at: now)
        expect(command.details?.toolName == "终端命令", "command patches remain excluded")
        var reset = CodexStreamDetails(state: state([message("old")]), at: now)
        reset.apply(patch(["turnHistory", "history", "islands"], [["entries": [["key": "old", "value": "old"]]]]), at: now)
        expect(reset.details?.turnID == "old-turn" && reset.details?.phase == .idle, "full ordered island replacement selects known turn")
        reset.apply(patch(["turnHistory", "history", "entitiesByKey", "old"], NSNull(), op: "remove"), at: now)
        expect(reset.needsSnapshot && reset.details == nil, "removing selected entity fails closed")
        var emptyIsland = CodexStreamDetails(state: state([message("before")]), at: now)
        emptyIsland.apply(patch(["turnHistory", "history", "islands", 1], ["id": "new-island", "entries": []], op: "add"), at: now)
        expect(emptyIsland.details?.turnID == "new-turn", "an empty new island preserves the most recent existing turn")
        emptyIsland.apply(patch(newKey, turn("empty-island-turn"), op: "add"), at: now)
        emptyIsland.apply(patch(["turnHistory", "history", "islands", 1, "entries", 0], ["key": "next", "value": "next"], op: "add"), at: now)
        expect(emptyIsland.details?.turnID == "empty-island-turn", "first entry of a new island becomes the most recent turn")
        let privateFixture = CodexStreamDetails(state: state([message("PUBLIC"), tool(), ["type": "reasoning", "content": ["REASONING_SECRET"], "summary": ["SUMMARY_SECRET"]], ["type": "userMessage", "text": "USER_SECRET"]]), at: now)
        let privateEncoded = String(decoding: try JSONEncoder().encode(privateFixture.details), as: UTF8.self)
        expect(privateEncoded.contains("PUBLIC") && !["ARGS_SECRET", "OUTPUT_SECRET", "REASONING_SECRET", "SUMMARY_SECRET", "USER_SECRET"].contains(where: privateEncoded.contains), "mixed real-shaped private fields never enter projected details")
        var noStatusTool = CodexStreamDetails(state: state([["type": "dynamicToolCall", "tool": "js"]]), at: now)
        expect(noStatusTool.details?.phase == .working && noStatusTool.details?.toolName == nil, "a tool without a verified active status cannot claim execution")
        noStatusTool.apply(patch(base + ["items", 0, "status"], "failed"), at: now)
        expect(noStatusTool.details?.phase == .working, "failed tool is inactive while the turn can still continue")
        print("Codex stream detail checks passed (\(count))")
    }
}
