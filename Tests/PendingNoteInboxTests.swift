import Foundation

@main
enum PendingNoteInboxTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    static func rejects(_ message: String, _ action: () throws -> Void) {
        do { try action(); fatalError("FAIL: expected rejection: \(message)") }
        catch { checks += 1 }
    }
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("workplace-inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("notes.json")
        let store = PendingNoteStore(url: url)
        let inbox = PendingNoteInbox(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        expect(inbox.notes.isEmpty && !inbox.canUndo, "fresh inbox is empty")
        try inbox.add("  修复登录\n保留换行与完整需求  ", at: date)
        let original = inbox.notes[0]
        expect(original.text == "修复登录\n保留换行与完整需求", "save trims only surrounding whitespace")
        expect(original.slot == 0 && original.createdAt == date, "new note keeps stable location and original time")
        let reopened = PendingNoteInbox(store: store)
        expect(reopened.notes == inbox.notes, "restart restores pending note without resetting wait")
        try inbox.add("第二条", at: date.addingTimeInterval(1))
        let second = inbox.notes[1]
        try inbox.remove(id: original.id)
        expect(inbox.notes == [second] && second.slot == 1, "removal leaves another visitor in its own slot")
        expect(inbox.canUndo, "marking handed off can be undone")
        try inbox.add("第三条", at: date.addingTimeInterval(2))
        expect(inbox.notes.last?.slot == 0, "new arrival can use a vacant slot")
        try inbox.undoRemoval()
        let returned = inbox.notes.first { $0.id == original.id }!
        expect(returned.createdAt == original.createdAt && returned.text == original.text, "undo restores identity and wait")
        expect(returned.slot == 2 && Set(inbox.notes.compactMap(\.slot)).count == 3, "undo uses a new vacant slot if needed")
        expect(!inbox.canUndo, "undo is consumed once")
        let before = inbox.notes
        rejects("blank notes") { try inbox.add(" \n ") }
        expect(inbox.notes == before && (try? store.read()) == before, "invalid input never changes memory or disk")
        for i in 3..<PendingNote.maximumCount { try inbox.add("访客 \(i)", at: date.addingTimeInterval(Double(i))) }
        let full = inbox.notes
        rejects("full inbox") { try inbox.add("第九位") }
        expect(inbox.notes == full, "capacity failure preserves all current visitors")
        try inbox.remove(id: original.id)
        try inbox.add("补充访客")
        expect(!inbox.canUndo, "full inbox disables undo until space is available")
        rejects("undo cannot exceed capacity") { try inbox.undoRemoval() }
        try inbox.remove(id: second.id)
        let writableBefore = inbox.notes
        // A directory at the destination makes atomic replacement fail even as
        // a privileged user; avoid relying on chmod-based permission tests.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        rejects("write failure") { try inbox.add("不要丢掉这个草稿") }
        expect(inbox.notes == writableBefore, "failed disk save never publishes a phantom arrival")
        rejects("remove failure") { try inbox.remove(id: writableBefore[0].id) }
        expect(inbox.notes == writableBefore, "failed removal keeps the visitor")
        try FileManager.default.removeItem(at: url)
        let corrupt = Data("{broken note file".utf8)
        try corrupt.write(to: url)
        let damaged = PendingNoteInbox(store: store, fallback: [original])
        expect(damaged.loadError != nil && damaged.notes == [original], "corrupt inbox shows valid last snapshot read-only")
        rejects("cannot overwrite damaged inbox") { try damaged.add("new") }
        expect((try? Data(contentsOf: url)) == corrupt, "damaged original file is preserved")
        print("PASS: \(checks) pending inbox checks")
    }
}
