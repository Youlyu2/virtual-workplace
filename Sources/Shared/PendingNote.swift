import Foundation

enum PendingNoteError: Error, LocalizedError {
    case emptyText, textTooLong, tooManyNotes
    case invalidIdentifier, duplicateIdentifier, invalidDate
    case invalidSlot, duplicateSlot, fileTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyText: return "请输入待办内容"
        case .textTooLong: return "每条待办最多 \(PendingNote.maximumTextLength) 个字"
        case .tooManyNotes: return "最多保留 \(PendingNote.maximumCount) 条待办"
        case .invalidIdentifier: return "待办标识不合法"
        case .duplicateIdentifier: return "待办标识重复"
        case .invalidDate: return "待办创建时间不合法"
        case .invalidSlot: return "待办位置不合法"
        case .duplicateSlot: return "待办位置重复"
        case .fileTooLarge: return "待办文件过大"
        }
    }
}

/// A personal reminder is independent of Codex sessions and task state.
struct PendingNote: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var text: String
    var createdAt: Date
    var slot: Int? = nil

    static let maximumCount = 8
    static let maximumTextLength = 2000

    static func normalizedText(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PendingNoteError.emptyText }
        guard value.count <= maximumTextLength else { throw PendingNoteError.textTooLong }
        return value
    }

    static func validate(_ notes: [PendingNote]) throws {
        guard notes.count <= maximumCount else { throw PendingNoteError.tooManyNotes }
        var identifiers = Set<String>()
        var slots = Set<Int>()
        for note in notes {
            guard !note.id.isEmpty, note.id.utf8.count <= 128,
                  note.id == note.id.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw PendingNoteError.invalidIdentifier
            }
            guard identifiers.insert(note.id).inserted else { throw PendingNoteError.duplicateIdentifier }
            guard note.text.count <= maximumTextLength else { throw PendingNoteError.textTooLong }
            _ = try normalizedText(note.text)
            guard note.createdAt.timeIntervalSince1970.isFinite,
                  note.createdAt.timeIntervalSince1970 >= 0 else { throw PendingNoteError.invalidDate }
            if let slot = note.slot {
                guard (0..<maximumCount).contains(slot) else { throw PendingNoteError.invalidSlot }
                guard slots.insert(slot).inserted else { throw PendingNoteError.duplicateSlot }
            }
        }
    }

    func waitingLabel(at now: Date) -> String {
        let elapsed = now.timeIntervalSince(createdAt)
        guard elapsed.isFinite, elapsed > 0 else { return "等待 0 分钟" }
        // Keep an invalid/extreme in-memory date from overflowing conversion.
        let minutes = Int(min(elapsed / 60, Double(Int.max / 2)))
        if minutes >= 24 * 60 {
            return "等待 \(minutes / (24 * 60)) 天 \((minutes / 60) % 24) 小时"
        }
        if minutes >= 60 { return "等待 \(minutes / 60) 小时 \(minutes % 60) 分" }
        return "等待 \(minutes) 分钟"
    }
}
