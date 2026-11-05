import Foundation
import Darwin

struct CodexRolloutObservation: Equatable {
    var details: CodexExecutionDetails?
    var startedAt: Date?
}

/// A deliberately small projection of user-visible transcript events. The
/// accumulator never retains a complete row, arguments, results or reasoning.
struct CodexRolloutAccumulator {
    private let threadID: String
    private var details: CodexExecutionDetails?
    private var startedAt: Date?
    private var currentTurn: String?
    private var ended = false
    private var calls: [(id: String, name: String)] = []
    var observation: CodexRolloutObservation { CodexRolloutObservation(details: details, startedAt: startedAt) }

    init(threadID: String) { self.threadID = threadID }

    mutating func consume(line: Data) {
        guard line.count <= CodexRolloutReader.maximumLineBytes,
              let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let kind = row["type"] as? String,
              let payload = row["payload"] as? [String: Any] else { return }
        let type = payload["type"] as? String ?? ""
        let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
        let explicitTurn = boundedID(payload["turn_id"] ?? metadata?["turn_id"])
        let date = Self.date(row["timestamp"]) ?? Self.date(payload["completed_at"])
            ?? Self.date(payload["started_at"])
        guard let date else { return }

        if let rowThread = boundedID(payload["thread_id"]), rowThread != threadID { return }
        if kind == "event_msg", type == "task_started" {
            currentTurn = explicitTurn ?? boundedID(payload["root_turn_id"])
            startedAt = Self.date(payload["started_at"]) ?? date
            ended = false; calls.removeAll()
            details = CodexExecutionDetails(phase: .working, updatedAt: date, turnID: currentTurn)
            return
        }
        // A new prompt is an observable boundary even in older event formats.
        if (kind == "event_msg" && type == "user_message")
            || (kind == "response_item" && type == "message" && payload["role"] as? String == "user") {
            // Modern logs write task_started before the matching prompt. That
            // prompt confirms the same turn and must not erase its real clock.
            let sameTurn = explicitTurn != nil && explicitTurn == currentTurn
            let sameLegacyStart = explicitTurn == nil && startedAt.map {
                (0...5).contains(date.timeIntervalSince($0))
            } == true
            if ended || !(sameTurn || sameLegacyStart) { startedAt = nil }
            currentTurn = explicitTurn ?? currentTurn
            calls.removeAll(); ended = false
            details = CodexExecutionDetails(phase: .working, updatedAt: date, turnID: currentTurn)
            return
        }
        if let currentTurn, let explicitTurn, currentTurn != explicitTurn { return }

        if kind == "event_msg", ["task_complete", "turn_aborted", "turn_failed"].contains(type) {
            if currentTurn == nil { currentTurn = explicitTurn }
            calls.removeAll(); ended = true
            var next = details ?? CodexExecutionDetails(phase: .idle, updatedAt: date, turnID: currentTurn)
            next.phase = .idle; next.toolName = nil; next.updatedAt = date
            if type == "task_complete", let text = Self.publicText(payload["last_agent_message"]) { next.latestUpdate = text }
            details = next
            return
        }
        guard !ended else { return }
        if currentTurn == nil { currentTurn = explicitTurn }

        if kind == "response_item", ["function_call", "custom_tool_call"].contains(type),
           let callID = boundedID(payload["call_id"]), let rawName = payload["name"] as? String,
           let name = Self.toolName(rawName, namespace: payload["namespace"] as? String) {
            calls.removeAll { $0.id == callID }
            if calls.count >= 64 { calls.removeFirst() }
            calls.append((callID, name))
            update(at: date, phase: .tool)
            return
        }
        if kind == "response_item", ["function_call_output", "custom_tool_call_output"].contains(type),
           let callID = boundedID(payload["call_id"]) {
            guard calls.contains(where: { $0.id == callID }) else { return }
            calls.removeAll { $0.id == callID }
            update(at: date, phase: calls.isEmpty ? .working : .tool)
            return
        }
        // The existence of a reasoning event can label the phase. Its text,
        // encrypted content and summaries are intentionally never consulted.
        if (kind == "response_item" && ["reasoning", "Reasoning"].contains(type))
            || (kind == "event_msg" && ["agent_reasoning", "agent_reasoning_raw_content"].contains(type)) {
            update(at: date, phase: calls.isEmpty ? .thinking : .tool)
            return
        }
        var text: String?
        if kind == "event_msg", type == "agent_message" {
            text = Self.publicText(payload["message"])
        } else if kind == "response_item", type == "message", payload["role"] as? String == "assistant",
                  payload["phase"] == nil || ["commentary", "final_answer", "final"].contains(payload["phase"] as? String ?? ""),
                  let blocks = payload["content"] as? [[String: Any]] {
            let strings = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "output_text" else { return nil }
                return block["text"] as? String
            }
            text = Self.publicText(strings.joined(separator: " "))
        }
        guard let text else { return }
        update(at: date, phase: calls.isEmpty ? .working : .tool)
        details?.latestUpdate = text
    }

    mutating func discardGap() {
        details = nil; startedAt = nil; currentTurn = nil; ended = false; calls.removeAll()
    }

    private mutating func update(at date: Date, phase: CodexExecutionPhase) {
        var next = details ?? CodexExecutionDetails(phase: phase, updatedAt: date, turnID: currentTurn)
        next.phase = phase; next.updatedAt = date; next.turnID = currentTurn
        if let latest = calls.last {
            let suffix = calls.count > 1 ? " (+\(calls.count - 1))" : ""
            next.toolName = String(latest.name.prefix(max(0, 120 - suffix.count))) + suffix
        } else { next.toolName = nil }
        details = next
    }

    private func boundedID(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty, string.utf8.count <= 128 else { return nil }
        return string
    }
    private static func toolName(_ name: String, namespace: String?) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./:-"))
        func clean(_ value: String) -> String { String(value.unicodeScalars.filter { allowed.contains($0) }.prefix(120)) }
        let tool = clean(name)
        guard !tool.isEmpty else { return nil }
        let space = namespace.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        return String((space.map { $0 + " / " } ?? "").appending(tool).prefix(120))
    }
    private static func publicText(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let flat = string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(320))
    }
    private static func date(_ value: Any?) -> Date? {
        if let string = value as? String {
            dateLock.lock(); defer { dateLock.unlock() }
            return fractionalDate.date(from: string) ?? wholeDate.date(from: string)
        }
        if let number = value as? NSNumber {
            var seconds = number.doubleValue
            if seconds > 100_000_000_000 { seconds /= 1000 }
            guard seconds.isFinite, seconds >= 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
    private static let dateLock = NSLock()
    private static let fractionalDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Bounded, incremental reads only inside the selected Codex sessions folder.
/// All state belongs to the observer's serial worker, never the AppKit thread.
final class CodexRolloutReader {
    static let maximumLineBytes = 2 * 1024 * 1024
    private static let maximumHeaderBytes = 256 * 1024
    private static let readBudget = 2 * 1024 * 1024
    private struct Cursor {
        var path: String
        var inode: UInt64
        var device: UInt64
        var offset: UInt64
        var pending = Data()
        var skipping = false
        var accumulator: CodexRolloutAccumulator
    }
    private let sessionsRoot: URL
    private var cursors: [String: Cursor] = [:]

    init(home: URL? = nil) {
        let codexHome: URL
        if let home { codexHome = home }
        else if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], path.hasPrefix("/") {
            codexHome = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let userHome = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            codexHome = URL(fileURLWithPath: userHome).appendingPathComponent(".codex", isDirectory: true)
        }
        sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    func retain(threadIDs: Set<String>) { cursors = cursors.filter { threadIDs.contains($0.key) } }

    func read(threadID: String, at path: String) -> CodexRolloutObservation? {
        guard !threadID.isEmpty, threadID.utf8.count <= 128, path.hasPrefix("/") else { return nil }
        let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(sessionsRoot.path + "/"), file.pathExtension == "jsonl" else {
            cursors.removeValue(forKey: threadID); return nil
        }
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { cursors.removeValue(forKey: threadID); return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_size >= 0 else {
            cursors.removeValue(forKey: threadID); return nil
        }
        let size = UInt64(info.st_size), inode = UInt64(info.st_ino), device = UInt64(info.st_dev)
        var cursor = cursors[threadID]
        if cursor?.path != file.path || cursor?.inode != inode || cursor?.device != device || size < (cursor?.offset ?? 0) {
            guard validateHeader(descriptor: descriptor, threadID: threadID, size: size) else {
                cursors.removeValue(forKey: threadID); return nil
            }
            let start = size > UInt64(Self.readBudget) ? size - UInt64(Self.readBudget) : 0
            cursor = Cursor(path: file.path, inode: inode, device: device, offset: start,
                            skipping: start > 0, accumulator: CodexRolloutAccumulator(threadID: threadID))
        }
        guard var next = cursor else { return nil }
        if size > next.offset {
            // A large burst can contain arbitrary history. Jump to its bounded
            // tail and forget prior activity rather than report a stale tool.
            if size - next.offset > UInt64(Self.readBudget) {
                next.offset = size - UInt64(Self.readBudget); next.pending.removeAll(keepingCapacity: false)
                next.skipping = true; next.accumulator.discardGap()
            }
            let wanted = min(Self.readBudget, Int(size - next.offset))
            var bytes = [UInt8](repeating: 0, count: wanted)
            let count = pread(descriptor, &bytes, wanted, off_t(next.offset))
            guard count >= 0 else { return nil }
            if count > 0 {
                next.offset += UInt64(count)
                consume(Data(bytes.prefix(count)), cursor: &next)
            }
        }
        cursors[threadID] = next
        return next.accumulator.observation
    }

    private func validateHeader(descriptor: Int32, threadID: String, size: UInt64) -> Bool {
        let amount = min(Self.maximumHeaderBytes, Int(min(size, UInt64(Self.maximumHeaderBytes))))
        guard amount > 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: amount)
        let count = pread(descriptor, &bytes, amount, 0)
        guard count > 0, let end = bytes.prefix(count).firstIndex(of: 10),
              let row = try? JSONSerialization.jsonObject(with: Data(bytes[..<end])) as? [String: Any],
              row["type"] as? String == "session_meta", let payload = row["payload"] as? [String: Any] else { return false }
        return payload["id"] as? String == threadID
    }

    private func consume(_ data: Data, cursor: inout Cursor) {
        var beginning = data.startIndex
        while beginning < data.endIndex, let newline = data[beginning...].firstIndex(of: 10) {
            if cursor.skipping { cursor.skipping = false }
            else if cursor.pending.count + data.distance(from: beginning, to: newline) <= Self.maximumLineBytes {
                cursor.pending.append(contentsOf: data[beginning..<newline])
                cursor.accumulator.consume(line: cursor.pending)
            } else { cursor.accumulator.discardGap() }
            cursor.pending.removeAll(keepingCapacity: true)
            beginning = data.index(after: newline)
        }
        if beginning < data.endIndex, !cursor.skipping {
            if cursor.pending.count + data.distance(from: beginning, to: data.endIndex) <= Self.maximumLineBytes {
                cursor.pending.append(contentsOf: data[beginning...])
            } else {
                cursor.pending.removeAll(keepingCapacity: false); cursor.skipping = true
                cursor.accumulator.discardGap()
            }
        }
    }
}
