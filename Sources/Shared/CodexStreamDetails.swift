import Foundation

/// A lossy reducer for the desktop's public conversation stream. It deliberately
/// retains no commands, arguments, outputs, user messages, or reasoning text.
/// Runtime active/idle status must still come from threadRuntimeStatus.
struct CodexStreamDetails {
    private struct Item {
        var id: String?
        var type: String
        var status: String?
        var phase: String?
        var text: String?
        var namespace: String?
        var tool: String?
        var completed: Bool
    }
    private struct Turn {
        var id: String?
        var status: String?
        var startedAt: Date?
        var items: [Int: Item]
        var itemCount: Int
    }
    private enum Format { case canonical, legacy, none }
    private var format = Format.none
    private var turns: [String: Turn] = [:]
    private var order: [String] = []
    private var pendingOrder: [String] = []
    private var lastIsland = 0
    private var entryCount = 0
    private var legacyCount = 0
    private var updatedAt: Date
    private(set) var needsSnapshot = false
    private static let maximumItems = 512
    private static let maximumTurns = 4

    init(state: [String: Any], at date: Date) {
        updatedAt = date
        if let historyContainer = state["turnHistory"] as? [String: Any],
           historyContainer["kind"] as? String == "canonical",
           let history = historyContainer["history"] as? [String: Any],
           let entities = history["entitiesByKey"] as? [String: Any],
           let islands = history["islands"] as? [[String: Any]] {
            format = .canonical
            lastIsland = max(0, islands.count - 1)
            entryCount = (islands.last?["entries"] as? [Any])?.count ?? 0
            order = Array(islands.flatMap { Self.keys($0["entries"]) }.suffix(Self.maximumTurns))
            for key in order {
                if let raw = entities[key] as? [String: Any] { turns[key] = Self.turn(raw) }
            }
        } else if let values = state["turns"] as? [[String: Any]] {
            format = .legacy; legacyCount = values.count
            for index in max(0, values.count - Self.maximumTurns)..<values.count {
                let key = String(index); order.append(key); turns[key] = Self.turn(values[index])
            }
        }
    }

    var turnStatus: String? { current?.status }
    var startedAt: Date? { current?.startedAt }
    var details: CodexExecutionDetails? {
        guard !needsSnapshot, let turn = current, let status = turn.status else { return nil }
        let items = turn.items.sorted { $0.key < $1.key }.map(\.value)
        let text = items.last(where: { $0.type == "agentMessage" && $0.text != nil })?.text
        let active = items.filter { Self.isTool($0.type) && Self.isActive($0.status) && !$0.completed }
        let ended = status != "inProgress"
        var phase: CodexExecutionPhase = ended ? .idle : .working
        var name: String?
        if !ended, let latest = active.last {
            phase = .tool
            name = Self.toolName(latest)
            if active.count > 1, let value = name {
                let suffix = " (+\(active.count - 1))"
                name = String(value.prefix(max(0, 120 - suffix.count))) + suffix
            }
        } else if !ended, let last = items.last, last.type == "reasoning", !last.completed {
            phase = .thinking
        }
        return CodexExecutionDetails(phase: phase, latestUpdate: text, toolName: name,
                                     updatedAt: updatedAt, turnID: turn.id)
    }

    mutating func apply(_ patch: [String: Any], at date: Date) {
        guard !needsSnapshot, let path = patch["path"] as? [Any],
              let op = patch["op"] as? String, ["add", "replace", "remove"].contains(op) else { return }
        if path.isEmpty {
            guard op != "remove", let state = patch["value"] as? [String: Any] else { invalidate(); return }
            self = CodexStreamDetails(state: state, at: date); return
        }
        guard let root = path[0] as? String else { invalidate(); return }
        if root == "turnHistory" { applyCanonical(path: Array(path.dropFirst()), patch: patch, at: date) }
        else if root == "turns" { applyLegacy(path: Array(path.dropFirst()), patch: patch, at: date) }
    }

    private var current: Turn? { needsSnapshot ? nil : order.last.flatMap { turns[$0] } }
    private mutating func invalidate() {
        turns.removeAll(); order.removeAll(); pendingOrder.removeAll(); needsSnapshot = true
    }
    private mutating func prune() {
        order = Array(order.suffix(Self.maximumTurns))
        pendingOrder = Array(pendingOrder.filter { !order.contains($0) }.suffix(Self.maximumTurns))
        // At most the current turn plus four recent/pending turn buffers survive.
        let prioritized = Array(pendingOrder.reversed()) + Array(order.reversed())
        var retained: [String] = []
        if let current = order.last { retained.append(current) }
        for key in prioritized where !retained.contains(key) && retained.count < Self.maximumTurns + 1 { retained.append(key) }
        let wanted = Set(retained)
        turns = turns.filter { wanted.contains($0.key) }
    }
    private mutating func applyCanonical(path: [Any], patch: [String: Any], at date: Date) {
        let op = patch["op"] as? String ?? ""
        if path.isEmpty {
            guard op != "remove", let value = patch["value"] as? [String: Any] else { invalidate(); return }
            self = CodexStreamDetails(state: ["turnHistory": value], at: date); return
        }
        guard format == .canonical else { invalidate(); return }
        guard path[0] as? String == "history" else {
            if path[0] as? String == "kind", patch["value"] as? String != "canonical" { invalidate() }
            return
        }
        if path.count == 1 {
            guard op != "remove", let value = patch["value"] as? [String: Any] else { invalidate(); return }
            self = CodexStreamDetails(state: ["turnHistory": ["kind": "canonical", "history": value]], at: date); return
        }
        guard let field = path[1] as? String else { invalidate(); return }
        if field == "entitiesByKey" {
            if path.count == 2 {
                guard op != "remove", let entities = patch["value"] as? [String: Any] else { invalidate(); return }
                turns.removeAll(); pendingOrder.removeAll()
                for key in order {
                    if let raw = entities[key] as? [String: Any] { turns[key] = Self.turn(raw) }
                }
                updatedAt = date; return
            }
            guard let key = Self.identifier(path[2], limit: 256) else { invalidate(); return }
            applyTurn(key: key, path: Array(path.dropFirst(3)), patch: patch, at: date)
        } else if field == "islands" {
            applyIslands(path: Array(path.dropFirst(2)), patch: patch, at: date)
        }
        // generation, boundary and pagination fields contain no displayed metadata.
    }
    private mutating func applyIslands(path: [Any], patch: [String: Any], at date: Date) {
        let op = patch["op"] as? String ?? ""
        if path.isEmpty {
            guard op != "remove", let islands = patch["value"] as? [[String: Any]] else { invalidate(); return }
            lastIsland = max(0, islands.count - 1)
            entryCount = (islands.last?["entries"] as? [Any])?.count ?? 0
            order = Array(islands.flatMap { Self.keys($0["entries"]) }.suffix(Self.maximumTurns))
        } else {
            guard let island = Self.index(path[0]) else { invalidate(); return }
            if path.count == 1 {
                if op == "remove" { if island == lastIsland { invalidate() }; return }
                guard island >= lastIsland, let value = patch["value"] as? [String: Any] else { return }
                let previous = island > lastIsland ? order : Array(order.dropLast(min(entryCount, order.count)))
                lastIsland = island; entryCount = (value["entries"] as? [Any])?.count ?? 0
                order = previous + Self.keys(value["entries"])
            } else {
                guard island == lastIsland else { return }
                guard path[1] as? String == "entries" else { return }
                if path.count == 2 {
                    guard op != "remove", let entries = patch["value"] as? [Any] else { invalidate(); return }
                    let previous = Array(order.dropLast(min(entryCount, order.count)))
                    entryCount = entries.count; order = previous + Self.keys(entries)
                } else {
                    let count = min(entryCount, order.count)
                    let previous = Array(order.dropLast(count))
                    var tail = Array(order.suffix(count))
                    guard path.count == 3, let index = Self.index(path[2]),
                          index >= max(0, entryCount - count), index <= entryCount else { invalidate(); return }
                    let offset = index - max(0, entryCount - count)
                    if op == "remove" {
                        guard offset < tail.count else { invalidate(); return }
                        tail.remove(at: offset); entryCount -= 1
                    } else {
                        guard let entry = patch["value"] as? [String: Any], let key = Self.identifier(entry["key"], limit: 256) else { invalidate(); return }
                        if op == "add" {
                            tail.insert(key, at: min(offset, tail.count)); entryCount += 1
                        } else {
                            guard offset < tail.count else { invalidate(); return }
                            tail[offset] = key
                        }
                    }
                    order = previous + tail
                }
            }
        }
        prune(); updatedAt = date
    }
    private mutating func applyLegacy(path: [Any], patch: [String: Any], at date: Date) {
        // Canonical history updates also assign turns = []. That compatibility
        // array must never replace the canonical current turn or its clock.
        guard format != .canonical else { return }
        let op = patch["op"] as? String ?? ""
        if path.isEmpty {
            guard op != "remove", let values = patch["value"] as? [[String: Any]] else { invalidate(); return }
            self = CodexStreamDetails(state: ["turns": values], at: date); return
        }
        // The canonical representation intentionally keeps the legacy array empty.
        guard format == .legacy else { return }
        guard let index = Self.index(path[0]), index <= legacyCount else { invalidate(); return }
        if path.count == 1 {
            if op == "add" || op == "remove" {
                var shifted: [String: Turn] = [:]
                for (key, value) in turns {
                    guard let old = Int(key), !(op == "remove" && old == index) else { continue }
                    let next = old >= index ? old + (op == "add" ? 1 : -1) : old
                    shifted[String(next)] = value
                }
                turns = shifted; legacyCount += op == "add" ? 1 : -1
            }
            if op != "remove" {
                guard let raw = patch["value"] as? [String: Any] else { invalidate(); return }
                turns[String(index)] = Self.turn(raw)
            }
            order = (max(0, legacyCount - Self.maximumTurns)..<legacyCount).map(String.init)
            prune(); updatedAt = date
        } else { applyTurn(key: String(index), path: Array(path.dropFirst()), patch: patch, at: date) }
    }
    private mutating func applyTurn(key: String, path: [Any], patch: [String: Any], at date: Date) {
        let op = patch["op"] as? String ?? ""
        if path.isEmpty {
            if op == "remove" {
                turns.removeValue(forKey: key)
                if order.last == key { invalidate() }
            } else {
                guard let raw = patch["value"] as? [String: Any] else { invalidate(); return }
                turns[key] = Self.turn(raw)
                if !order.contains(key) { pendingOrder.append(key) }
                prune()
            }
            updatedAt = date; return
        }
        guard var turn = turns[key], let field = path[0] as? String else {
            // Old turns outside the bounded retained tail are intentionally ignored.
            if order.last == key { invalidate() }; return
        }
        if path.count == 1 {
            switch field {
            case "turnId": turn.id = op == "remove" ? nil : Self.identifier(patch["value"])
            case "status": turn.status = op == "remove" ? nil : Self.status(patch["value"])
            case "turnStartedAtMs": turn.startedAt = op == "remove" ? nil : Self.date(patch["value"])
            case "items":
                guard op != "remove", let items = patch["value"] as? [[String: Any]] else { invalidate(); return }
                turn.items = Self.items(items, completed: [:]); turn.itemCount = items.count
            case "completedItemIds":
                let completed = patch["value"] as? [String: Any] ?? [:]
                for index in turn.items.keys {
                    if let id = turn.items[index]?.id, let value = completed[id] as? Bool { turn.items[index]?.completed = value }
                }
            default: return
            }
        } else if field == "items" {
            guard let index = Self.index(path[1]), index <= turn.itemCount else { invalidate(); return }
            if path.count == 2 {
                if op == "add" || op == "remove" {
                    var shifted: [Int: Item] = [:]
                    for (old, item) in turn.items where !(op == "remove" && old == index) {
                        shifted[old >= index ? old + (op == "add" ? 1 : -1) : old] = item
                    }
                    turn.items = shifted; turn.itemCount += op == "add" ? 1 : -1
                }
                if op != "remove" {
                    guard let raw = patch["value"] as? [String: Any] else { invalidate(); return }
                    let previous = turn.items[index]
                    var next = Self.item(raw, completed: [:])
                    if op == "replace", previous?.id == next.id, previous?.completed == true { next.completed = true }
                    turn.items[index] = next
                }
                turn.items = turn.items.filter { $0.key >= max(0, turn.itemCount - Self.maximumItems) }
            } else if var item = turn.items[index], let itemField = path[2] as? String {
                if path.count == 3 {
                    switch itemField {
                    case "status": item.status = op == "remove" ? nil : Self.identifier(patch["value"])
                    case "text":
                        if item.type == "agentMessage", Self.publicPhase(item.phase) { item.text = op == "remove" ? nil : Self.publicText(patch["value"]) }
                    case "phase":
                        item.phase = op == "remove" ? nil : Self.identifier(patch["value"])
                        if !Self.publicPhase(item.phase) { item.text = nil }
                    case "completedAtMs": item.completed = op != "remove" && Self.date(patch["value"]) != nil
                    case "id": item.id = op == "remove" ? nil : Self.identifier(patch["value"])
                    case "namespace", "server":
                        if Self.isTool(item.type) { item.namespace = op == "remove" ? nil : Self.cleanName(patch["value"]) }
                    case "tool":
                        if item.type == "dynamicToolCall" || item.type == "mcpToolCall" { item.tool = op == "remove" ? nil : Self.cleanName(patch["value"]) }
                    case "type": invalidate(); return
                    default: return
                    }
                    turn.items[index] = item
                }
                // In particular, nested reasoning/content and arguments/output patches are ignored.
            }
        } else if field == "completedItemIds", path.count == 2, let id = path[1] as? String {
            for index in turn.items.keys where turn.items[index]?.id == id {
                turn.items[index]?.completed = op != "remove" && (patch["value"] as? Bool == true)
            }
        } else { return }
        turns[key] = turn; updatedAt = date
    }

    private static func turn(_ raw: [String: Any]) -> Turn {
        let values = raw["items"] as? [[String: Any]] ?? []
        return Turn(id: identifier(raw["turnId"]), status: status(raw["status"]),
                    startedAt: date(raw["turnStartedAtMs"]),
                    items: items(values, completed: raw["completedItemIds"] as? [String: Any] ?? [:]), itemCount: values.count)
    }
    private static func items(_ values: [[String: Any]], completed: [String: Any]) -> [Int: Item] {
        var result: [Int: Item] = [:]
        for index in max(0, values.count - maximumItems)..<values.count { result[index] = item(values[index], completed: completed) }
        return result
    }
    private static func item(_ raw: [String: Any], completed: [String: Any]) -> Item {
        let id = identifier(raw["id"])
        let type = identifier(raw["type"]) ?? "unknown"
        let phase = identifier(raw["phase"])
        // Only user-visible assistant messages are read. No generic string walker.
        let text = type == "agentMessage" && publicPhase(phase) ? publicText(raw["text"]) : nil
        let tool = type == "dynamicToolCall" || type == "mcpToolCall" ? cleanName(raw["tool"]) : nil
        let namespace = isTool(type) ? cleanName(raw["namespace"] ?? raw["server"]) : nil
        return Item(id: id, type: type, status: identifier(raw["status"]), phase: phase, text: text,
                    namespace: namespace, tool: tool,
                    completed: (id.flatMap { completed[$0] as? Bool } ?? false) || date(raw["completedAtMs"]) != nil)
    }
    private static func keys(_ value: Any?) -> [String] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.suffix(maximumTurns).compactMap { identifier($0["key"], limit: 256) }
    }
    private static func identifier(_ value: Any?, limit: Int = 128) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= limit else { return nil }; return value
    }
    private static func index(_ value: Any) -> Int? {
        guard let value = value as? Int, value >= 0, value <= 100_000 else { return nil }; return value
    }
    private static func status(_ value: Any?) -> String? {
        guard let value = value as? String, ["inProgress", "completed", "failed", "interrupted"].contains(value) else { return nil }; return value
    }
    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let milliseconds = number.doubleValue
        guard milliseconds.isFinite, milliseconds >= 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
    private static func publicPhase(_ phase: String?) -> Bool { phase == "commentary" || phase == "final_answer" || phase == "final" }
    private static func isTool(_ type: String) -> Bool { ["dynamicToolCall", "mcpToolCall", "commandExecution", "fileChange"].contains(type) }
    private static func isActive(_ status: String?) -> Bool { status == "inProgress" || status == "running" }
    private static func publicText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let text = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(320))
    }
    private static func cleanName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./:-"))
        let text = String(value.unicodeScalars.filter { allowed.contains($0) }.prefix(120))
        return text.isEmpty ? nil : text
    }
    private static func toolName(_ item: Item) -> String? {
        if item.type == "commandExecution" { return "终端命令" }
        if item.type == "fileChange" { return "修改文件" }
        guard let tool = item.tool else { return nil }
        return String(((item.namespace.map { $0 + " / " } ?? "") + tool).prefix(120))
    }
}
