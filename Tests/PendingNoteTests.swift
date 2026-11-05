import Foundation
import Dispatch

@main
enum PendingNoteTests {
    private static var checks = 0
    private static let now = Date(timeIntervalSince1970: 1_793_800_000)

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do {
            let result = try value()
            precondition(result, "FAIL: \(message)")
        } catch { fatalError("FAIL: \(message): \(error)") }
    }

    private final class FailureFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        func read() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private static func rejects(_ message: String, _ body: () throws -> Void) {
        var failed = false
        do { try body() } catch { failed = true }
        expect(failed, message)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VirtualWorkplace-PendingNoteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("notes/pending-notes.json")
        let store = PendingNoteStore(url: url)

        expect(try store.read().isEmpty, "missing notes are an empty inbox")
        expect(!FileManager.default.fileExists(atPath: url.path), "reading missing notes does not create or rewrite storage")
        expect(try PendingNote.normalizedText(" \n 第一行\n  第二行 \n") == "第一行\n  第二行",
               "normalization trims outer whitespace while preserving multiline content")
        rejects("blank notes are rejected") { _ = try PendingNote.normalizedText(" \t\n　") }
        expect(try PendingNote.normalizedText(String(repeating:"字",count:2000)).count == 2000,
               "the full Unicode character limit is accepted")
        rejects("text beyond the character limit is rejected") {
            _ = try PendingNote.normalizedText(String(repeating:"字",count:2001))
        }

        let first = PendingNote(id:"first",text:"验证接口\n保留错误示例",createdAt:now,slot:2)
        let second = PendingNote(id:"second",text:"整理设计稿",createdAt:now.addingTimeInterval(-90),slot:5)
        let notes = [first, second]
        try PendingNote.validate(notes)
        try store.write(notes)
        expect(try store.read() == notes, "notes round-trip with identity, multiline text, date and seat intact")
        expect(try PendingNoteStore(url:url).read() == notes, "a new process/store instance restores the same notes")
        let stored = try Data(contentsOf:url)
        rejects("duplicate note identifiers are rejected") { try store.write([first,first]) }
        expect(try Data(contentsOf:url) == stored, "an invalid write leaves the previous durable file unchanged")
        rejects("more than eight notes are rejected") {
            try PendingNote.validate((0..<9).map { PendingNote(id:"note-\($0)",text:"item",createdAt:now) })
        }
        try PendingNote.validate((0..<8).map { (index: Int) in
            PendingNote(id:"note-\(index)",text:"item",createdAt:now,slot:index)
        })
        expect(true, "eight independently occupied seats are accepted")
        for invalidID in ["", " ", "bad\nid"] {
            rejects("invalid identifier \(invalidID.debugDescription) is rejected") {
                try PendingNote.validate([PendingNote(id:invalidID,text:"item",createdAt:now)])
            }
        }
        rejects("stored blank text is rejected") {
            try PendingNote.validate([PendingNote(text:"\n ",createdAt:now)])
        }
        rejects("stored untrimmed text cannot evade the length limit") {
            try PendingNote.validate([PendingNote(text:String(repeating:" ",count:2000)+"x",createdAt:now)])
        }
        for invalidDate in [Date(timeIntervalSince1970:-1), Date(timeIntervalSince1970:.infinity),
                            Date(timeIntervalSince1970:.nan)] {
            rejects("invalid note dates are rejected before encoding") {
                try PendingNote.validate([PendingNote(text:"item",createdAt:invalidDate)])
            }
        }
        for slot in [-1,8] {
            rejects("seat \(slot) outside the fixed inbox range is rejected") {
                try PendingNote.validate([PendingNote(text:"item",createdAt:now,slot:slot)])
            }
        }
        rejects("two notes cannot occupy the same explicit seat") {
            try PendingNote.validate([first,PendingNote(id:"another",text:"item",createdAt:now,slot:2)])
        }
        let oldNoteData = Data("{\"id\":\"legacy\",\"text\":\"legacy note\",\"createdAt\":800000000}".utf8)
        expect(try JSONDecoder().decode(PendingNote.self,from:oldNoteData).slot == nil,
               "notes without a seat remain decodable for deterministic legacy layout")

        expect(first.waitingLabel(at:now.addingTimeInterval(-120)) == "等待 0 分钟", "future creation dates clamp waiting to zero")
        expect(first.waitingLabel(at:now.addingTimeInterval(59)) == "等待 0 分钟", "sub-minute waits stay at zero minutes")
        expect(first.waitingLabel(at:now.addingTimeInterval(3*60+59)) == "等待 3 分钟", "minute labels floor partial minutes")
        expect(first.waitingLabel(at:now.addingTimeInterval(2*3600+4*60+59)) == "等待 2 小时 4 分", "hour labels retain the remaining minutes")
        expect(first.waitingLabel(at:now.addingTimeInterval(24*3600)) == "等待 1 天 0 小时", "exactly one day has a zero-hour remainder")
        var utc = Calendar(identifier:.gregorian); utc.timeZone = TimeZone(secondsFromGMT:0)!
        let yearEnd = utc.date(from:DateComponents(year:2026,month:12,day:31,hour:23,minute:59))!
        let crossing = PendingNote(text:"跨日",createdAt:yearEnd)
        expect(crossing.waitingLabel(at:yearEnd.addingTimeInterval(26*3600+60)) == "等待 1 天 2 小时",
               "elapsed waiting remains correct across midnight and a year boundary")
        expect(first.waitingLabel(at:Date(timeIntervalSince1970:.infinity)) == "等待 0 分钟",
               "invalid in-memory clocks cannot crash a waiting label")

        let legacyJSON = Data("{\"schemaVersion\":1,\"mode\":\"automatic\",\"preferredPosture\":\"sitting\",\"tasks\":[],\"updatedAt\":800000000,\"lastWorkEndedAt\":null,\"isOnline\":true,\"demoRunning\":false}".utf8)
        let legacy = try JSONDecoder().decode(SceneSnapshot.self,from:legacyJSON)
        expect(legacy.pendingNotes == nil, "snapshots from before notes remain compatible")
        var snapshot = SceneSnapshot.empty(now:now)
        snapshot.tasks = [WorkplaceTask(id:"codex-task",title:"正在工作",status:.running,slot:2)]
        let priorPose = snapshot.resolvedPose(at:now), priorActivity = snapshot.resolvedActivity(at:now)
        snapshot.pendingNotes = notes
        expect(snapshot.resolvedPose(at:now) == priorPose && snapshot.resolvedActivity(at:now) == priorActivity,
               "notes do not change Codex-driven pose or activity")
        expect(snapshot.tasks.count == 1 && snapshot.tasks.first?.slot == 2,
               "a note seat is independent of Codex session counts and slots")
        var idle = SceneSnapshot.empty(now:now); idle.pendingNotes = notes
        expect(idle.resolvedPose(at:now) == .slacking && idle.resolvedActivity(at:now) == .resting,
               "personal notes alone never make an idle employee appear to work")
        let state = StateStore(url:root.appendingPathComponent("state.json"))
        try state.write(snapshot)
        expect(try state.read().pendingNotes == notes, "the shared snapshot transports notes to other hosts")
        let validState = try Data(contentsOf:state.url)
        snapshot.pendingNotes = [first,first]
        rejects("StateStore rejects malformed attached notes") { try state.write(snapshot) }
        expect(try Data(contentsOf:state.url) == validState, "invalid attached notes cannot replace a valid shared snapshot")

        let corrupted = Data("{invalid pending-note JSON".utf8)
        try corrupted.write(to:url)
        rejects("corrupt note JSON is reported") { _ = try store.read() }
        expect(try Data(contentsOf:url) == corrupted, "corrupt note files are preserved byte-for-byte for recovery")
        let oversized = Data(repeating:65,count:PendingNoteStore.maximumFileSize+1)
        try oversized.write(to:url)
        rejects("oversized files are rejected before decoding") { _ = try store.read() }
        expect(try Data(contentsOf:url) == oversized, "an oversized file is not silently reset")
        try store.write(notes)
        let beforeLargeWrite = try Data(contentsOf:url)
        let longGrapheme = "a" + String(repeating:"\u{0301}",count:100)
        let byteHeavyNote = PendingNote(text:String(repeating:longGrapheme,count:2000),createdAt:now)
        expect(byteHeavyNote.text.count == 2000, "byte-limit fixture remains within the character limit")
        rejects("encoded size is bounded even for large Unicode grapheme clusters") { try store.write([byteHeavyNote]) }
        expect(try Data(contentsOf:url) == beforeLargeWrite, "an oversized encoded write preserves existing notes")
        snapshot.pendingNotes = [byteHeavyNote]
        rejects("shared snapshots apply the same encoded-size bound") { try state.write(snapshot) }
        expect(try Data(contentsOf:state.url) == validState, "oversized snapshots leave prior shared state intact")

        // Readers in another host should see an old or new complete array,
        // never a partially rewritten JSON document during an atomic save.
        let writers = DispatchGroup()
        let writerFailed = FailureFlag()
        writers.enter()
        DispatchQueue.global(qos:.utility).async {
            defer { writers.leave() }
            do {
                for count in 0..<50 { try store.write(count.isMultiple(of:2) ? notes : [first]) }
            } catch {
                writerFailed.set()
            }
        }
        var partialRead = false
        for _ in 0..<120 {
            do { let value = try store.read(); if value != notes && value != [first] { partialRead = true } }
            catch { partialRead = true }
        }
        writers.wait()
        expect(!writerFailed.read() && !partialRead, "concurrent readers only observe complete old or new arrays")
        print("PASS: \(checks) pending-note model, persistence, compatibility and elapsed-time checks")
    }
}
