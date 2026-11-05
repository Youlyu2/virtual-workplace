import Foundation

/// Notes are durable user input, independent of transient Codex snapshots.
/// Publish mutations only after the separate inbox file has been saved.
final class PendingNoteInbox {
    private let store: PendingNoteStore
    private(set) var notes: [PendingNote] = []
    private(set) var loadError: String?
    private var lastRemoved: PendingNote?
    var canUndo: Bool { lastRemoved != nil && notes.count < PendingNote.maximumCount && loadError == nil }

    init(store: PendingNoteStore, fallback: [PendingNote] = []) {
        self.store = store
        do {
            notes = try store.read()
        } catch {
            // A valid shared snapshot may still show the last known notes, but
            // never silently overwrite a damaged inbox with that fallback.
            if (try? PendingNote.validate(fallback)) != nil { notes = fallback }
            loadError = "无法读取门外待办，原文件已保留：\(store.url.path)\n\(error.localizedDescription)"
        }
    }

    func add(_ raw: String, at date: Date = Date()) throws {
        try ensureWritable()
        let text = try PendingNote.normalizedText(raw)
        var next = notes
        let note = PendingNote(text: text, createdAt: date, slot: availableSlot(in: next))
        next.append(note)
        try store.write(next)
        notes = next
    }

    func remove(id: String) throws {
        try ensureWritable()
        guard let note = notes.first(where: { $0.id == id }) else { return }
        let next = notes.filter { $0.id != id }
        try store.write(next)
        notes = next
        lastRemoved = note
    }

    func undoRemoval() throws {
        try ensureWritable()
        guard var note = lastRemoved else { return }
        if note.slot == nil || notes.contains(where: { $0.slot == note.slot }) {
            note.slot = availableSlot(in: notes)
        }
        let next = (notes + [note]).sorted { $0.createdAt < $1.createdAt }
        try store.write(next)
        notes = next
        lastRemoved = nil
    }

    private func availableSlot(in notes: [PendingNote]) -> Int? {
        let occupied = Set(notes.compactMap(\.slot))
        return (0..<PendingNote.maximumCount).first { !occupied.contains($0) }
    }

    private func ensureWritable() throws {
        if let loadError {
            throw NSError(domain: "VirtualWorkplace.PendingNotes", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: loadError])
        }
    }
}
