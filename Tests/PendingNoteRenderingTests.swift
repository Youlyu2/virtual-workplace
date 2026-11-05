import AppKit
import ImageIO
import Darwin

@main enum PendingNoteRenderingTests {
    private static var checks = 0
    private static let date = Date(timeIntervalSince1970: 1_793_811_600)
    private static let nativeSize = CGSize(width: 1672, height: 941)
    private static let texts = ["把虚拟工位的屏保入口整理一下", "回顾开发机上昨天的 Codex 任务",
        "确认新版图标与双屏风景的衔接", "午休后整理会议里的三项后续工作",
        "给猫咪的散步动作再留一点停顿", "核对长任务的状态与等待确认提示",
        "写下周计划\n把项目文档整理给团队", "📌 这是一条比较长的待办说明，用来确认摘要会正确换行并省略，完整内容仍然保存在待办面板。"]
    private static func fixtures(_ count: Int) -> [PendingNote] {
        (0..<count).map { index in
            PendingNote(id: "note-fixture-\(index)", text: texts[index],
                createdAt: date.addingTimeInterval(-Double([15, 180, 7440, 93600, 400, 720, 2400, 99][index])), slot: index)
        }
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), "FAIL: \(message)")
    }
    private static func context(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func render(_ notes: [PendingNote]?, size: CGSize = nativeSize,
                               background: WorkplaceBackground = .outdoors,
                               world: SceneWorld = SceneWorld(timeMode: .day),
                               at now: Date = date, uptime: TimeInterval = 0,
                               reduceMotion: Bool = true) -> CGContext {
        let c = context(size)
        var snapshot = SceneSnapshot.empty(now: date)
        snapshot.mode = .sitting; snapshot.pendingNotes = notes; snapshot.world = world
        // These checks isolate visitor geometry/window leakage. The separate
        // pending-weather suite covers notes intentionally changing scenery.
        snapshot.world?.pendingWeatherEnabled = false
        SceneRenderer.draw(in: c, bounds: CGRect(origin: .zero, size: size), snapshot: snapshot,
            time: uptime, reduceMotion: reduceMotion, now: now, background: background)
        return c
    }
    private static func same(_ a: CGContext, _ b: CGContext, in rect: CGRect? = nil) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        let r = rect ?? CGRect(x: 0, y: 0, width: a.width, height: a.height)
        for y in Int(r.minY)..<Int(r.maxY) {
            let offset = (a.height - 1 - y) * a.bytesPerRow + Int(r.minX) * 4
            if memcmp(a.data!.advanced(by: offset), b.data!.advanced(by: offset), Int(r.width) * 4) != 0 { return false }
        }
        return true
    }
    private static func save(_ c: CGContext, _ name: String) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/pending-note-review")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name + ".png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, c.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    private static func checkGeometry(_ notes: [PendingNote], size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        for second in stride(from: 0.0, through: 80.0, by: 2.7) {
            let people = PendingNoteVisitors.placements(notes: notes, bounds: bounds,
                at: date.addingTimeInterval(second), reduceMotion: false)
            expect(people.count == notes.count, "every note has a visible visitor at \(size)")
            for person in people {
                expect(bounds.contains(person.bubble) && bounds.contains(person.spriteBounds),
                    "bubble and full sprite stay inside \(size)")
                expect(person.cell.contains(person.bubble) && person.cell.contains(person.spriteBounds),
                    "a visitor never leaves its stable non-overlapping seat")
                expect(person.feet.y < size.height * 0.25 && person.bubble.maxY < size.height * 0.47,
                    "staggered visitors stand on grass or path, never on the fence or distant world")
                expect(!person.spriteBounds.intersects(person.bubble),
                    "a larger visitor's head never enters its own note card")
                let hudScale = min(size.height / 941, size.width / 400)
                expect(person.spriteBounds.minY > 60 * hudScale,
                    "larger visitors leave the bottom weather and clock HUD readable")
                for other in people where other.note.id != person.note.id {
                    expect(!person.bubble.intersects(other.bubble) && !person.spriteBounds.intersects(other.bubble)
                           && !person.spriteBounds.intersects(other.spriteBounds),
                        "staggered walking boundaries keep visitors and neighboring note cards separate")
                }
            }
        }
    }

    static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        expect(PendingVisitorSprites.isAvailable, "the distinct four-direction visitor atlas is packaged")
        let notes = fixtures(8), bounds = CGRect(origin: .zero, size: nativeSize)
        for count in [0, 1, 4, 8] {
            let selected = fixtures(count)
            let image = render(selected); save(image, "visitors-\(count)-day")
            expect(PendingNoteVisitors.placements(notes: selected, bounds: bounds, at: date, reduceMotion: true).count == count,
                "\(count) notes produces exactly \(count) visitors")
        }
        expect(same(render(nil), render([])), "old snapshots and an empty note list leave the existing outdoor scene identical")
        expect(same(render(notes, background: .room), render([], background: .room)),
            "notes never render into the room or its window glass")
        expect(same(render(notes), render([]), in: CGRect(x: 0, y: 450, width: 1672, height: 491)),
            "larger near-ground visitors and their cards leave the upper distant world untouched")
        let current = PendingNoteVisitors.placements(notes: notes, bounds: bounds, at: date, reduceMotion: false)
        expect(current.allSatisfy { (140...150).contains($0.spriteHeight) },
            "full-size visitors are about 1.7 times the old 82-pixel sprites")
        expect(Set(current.map(\.slot)).count == 8 && Set(current.map(\.accent)).count == 8,
            "all eight visible identities have distinct stable slots and note accents")
        let solo = PendingNoteVisitors.placements(notes: [notes[0]], bounds: bounds, at: date, reduceMotion: false)[0]
        expect(solo.spriteHeight == current[0].spriteHeight && solo.feet == current[0].feet,
            "a single visitor remains full-size and does not jump when neighbors arrive")
        let removed = PendingNoteVisitors.placements(notes: Array(notes.dropFirst()), bounds: bounds, at: date, reduceMotion: false)
        for visitor in removed {
            let original = current.first { $0.note.id == visitor.note.id }!
            expect(visitor.slot == original.slot && visitor.feet == original.feet && visitor.bubble == original.bubble
                   && visitor.accent == original.accent && visitor.motion == original.motion,
                "deleting a different note preserves \(visitor.note.id)'s seat, identity and walking phase")
        }
        let reversed = PendingNoteVisitors.placements(notes: notes.reversed(), bounds: bounds, at: date, reduceMotion: false)
        expect(zip(current, reversed).allSatisfy { $0.note.id == $1.note.id && $0.feet == $1.feet },
            "snapshot order does not change visitor identity or placement")
        var legacy = notes; for index in legacy.indices { legacy[index].slot = nil }
        let legacyA = PendingNoteVisitors.placements(notes: legacy, bounds: bounds, at: date, reduceMotion: true)
        let legacyB = PendingNoteVisitors.placements(notes: legacy.reversed(), bounds: bounds, at: date, reduceMotion: true)
        expect(Set(legacyA.map(\.slot)).count == 8 && zip(legacyA, legacyB).allSatisfy { $0.slot == $1.slot },
            "legacy nil slots receive deterministic collision-free seats")

        var directions = Set<PixelWalkDirection>(), moving = false, paused = false
        var previous = PendingNoteVisitors.motion(for: notes[0].id, at: date, reduceMotion: false)
        for step in 1...1800 {
            let next = PendingNoteVisitors.motion(for: notes[0].id,
                at: date.addingTimeInterval(Double(step) / 20), reduceMotion: false)
            let dx = abs(next.offset.x - previous.offset.x), dy = abs(next.offset.y - previous.offset.y)
            expect(dx < 0.0001 || dy < 0.0001, "a visitor walks only one cardinal axis at a time")
            moving = moving || next.isMoving; paused = paused || !next.isMoving
            if next.isMoving { directions.insert(next.direction) }
            previous = next
        }
        expect(directions.count == 4 && moving && paused, "the quiet walking loop includes four headings and planted pauses")
        let stopped = PendingNoteVisitors.placements(notes: notes, bounds: bounds, at: date, reduceMotion: true)
        let stoppedLater = PendingNoteVisitors.placements(notes: notes, bounds: bounds,
            at: date.addingTimeInterval(65), reduceMotion: true)
        expect(zip(stopped, stoppedLater).allSatisfy { $0.feet == $1.feet && !$0.motion.isMoving && !$1.motion.isMoving },
            "reduce motion keeps every visitor still")
        expect(stopped[0].waitingLabel != stoppedLater[0].waitingLabel,
            "real waiting time still updates while motion is reduced")
        expect(stopped.allSatisfy { $0.waitingLabel == $0.note.waitingLabel(at: date) },
            "bubble waiting labels use the persisted creation date")
        expect(same(render(notes, uptime: 0, reduceMotion: false), render(notes, uptime: 90_000, reduceMotion: false)),
            "app and saver uptime never change the shared visitor phase")
        expect(PendingNoteVisitors.summary("  整理\n  项目   文档 ") == "整理 项目 文档"
               && PendingNoteVisitors.summary(String(repeating: "🙂", count: 2000)).count <= 56,
            "summary normalization keeps long Unicode notes bounded without changing stored text")
        for (size, name) in [(nativeSize, "16-9"), (CGSize(width: 1512, height: 982), "16-10"),
                             (CGSize(width: 2560, height: 1080), "ultrawide"),
                             (CGSize(width: 800, height: 1200), "portrait"),
                             (CGSize(width: 640, height: 480), "compact"),
                             (CGSize(width: 410, height: 230), "panel-preview")] {
            checkGeometry(notes, size: size)
            save(render(notes, size: size, reduceMotion: false), "visitors-8-\(name)")
        }
        let rainyNight = render(notes, world: SceneWorld(weather: .rain, timeMode: .night), reduceMotion: false)
        save(rainyNight, "visitors-8-rain-night")
        expect(!same(rainyNight, render([] , world: SceneWorld(weather: .rain, timeMode: .night), reduceMotion: false)),
            "visitor cards remain visible in rainy night scenes")
        print("PASS: \(checks) pending-note visitor identity, cardinal motion, waiting-time, layout and rendering checks")
        print("PREVIEWS: build/pending-note-review")
    }
}
