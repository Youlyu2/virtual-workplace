import AppKit
import ImageIO

@main enum WorldRenderingTests {
    static var checks = 0
    static let size = CGSize(width: 1672, height: 941)
    static let now = Date(timeIntervalSince1970: 1_793_661_610)
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), "FAIL: \(message)")
    }
    static func render(_ world: SceneWorld, background: WorkplaceBackground = .outdoors,
                       at date: Date = now, time: Double = 12, reduceMotion: Bool = false,
                       size: CGSize = size, notes: [PendingNote] = [], taskCount: Int = 1,
                       action: SceneAction? = nil, completedToday: Int = 0, mode: EmployeeMode = .sitting) -> CGContext {
        let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                          bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        var snapshot = SceneSnapshot.empty(now: date)
        snapshot.mode = mode; snapshot.world = world; snapshot.pendingNotes = notes
        snapshot.world?.weatherMode = .manual
        snapshot.action = action
        snapshot.completedToday = completedToday
        snapshot.tasks = (0..<taskCount).map { slot in
            WorkplaceTask(id: "fixture-\(slot)", title: "共享世界渲染测试", status: .running, slot: slot)
        }
        SceneRenderer.draw(in: c, bounds: CGRect(origin: .zero, size: size), snapshot: snapshot,
                           time: time, reduceMotion: reduceMotion, now: date, background: background)
        return c
    }
    static func hash(_ c: CGContext, rect: CGRect? = nil) -> UInt64 {
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        var result: UInt64 = 1469598103934665603
        if let rect {
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let i = ((c.height - 1 - y) * c.width + x) * 4
                    for channel in 0..<4 { result = (result ^ UInt64(p[i + channel])) &* 1099511628211 }
                }
            }
        } else {
            for i in stride(from: 0, to: c.width * c.height * 4, by: 37) {
                result = (result ^ UInt64(p[i])) &* 1099511628211
            }
        }
        return result
    }
    static func luminance(_ c: CGContext, x: Int, y: Int) -> Double {
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        let i = ((c.height - 1 - y) * c.width + x) * 4
        return 0.2126 * Double(p[i]) + 0.7152 * Double(p[i + 1]) + 0.0722 * Double(p[i + 2])
    }
    static func save(_ c: CGContext, name: String) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/world-rendering")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(name + ".png")
        let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, c.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    static func main() {
        _ = NSApplication.shared
        expect(SceneRenderer.hasOutdoorAssets, "the packaged outdoor artwork loads")
        expect(RoomAssets.usesFlatForeground ? RoomAssets.nightBackground == nil && RoomAssets.rugPatch == nil
               : RoomAssets.nightBackground != nil,
               "flat room uses matching native night grading without old perspective patches")
        let day = render(SceneWorld(timeMode: .day))
        let night = render(SceneWorld(timeMode: .night))
        let sunset = render(SceneWorld(timeMode: .sunset))
        expect(luminance(night, x: 1000, y: 850) < luminance(day, x: 1000, y: 850) * 0.6,
               "night visibly darkens the sky")
        expect(Set([hash(day), hash(night), hash(sunset)]).count == 3, "day, sunset and night have distinct lighting")
        save(day, name: "outdoors-day"); save(night, name: "outdoors-night"); save(sunset, name: "outdoors-sunset")
        var variants = Set<UInt64>()
        for weather in WorldWeather.allCases {
            let image = render(SceneWorld(weather: weather, timeMode: .day))
            variants.insert(hash(image)); save(image, name: "outdoors-\(weather.rawValue)")
        }
        expect(variants.count == WorldWeather.allCases.count, "all four weather choices visibly differ")
        let sameTime = render(SceneWorld(weather: .rain, timeMode: .night), time: 99_999)
        let sameTimeOtherHost = render(SceneWorld(weather: .rain, timeMode: .night), time: 0)
        expect(hash(sameTime) == hash(sameTimeOtherHost), "host uptime does not change the shared outdoor world phase")
        expect(hash(render(SceneWorld(weather: .snow, timeMode: .day)))
               != hash(render(SceneWorld(weather: .snow, timeMode: .day), at: now.addingTimeInterval(1))),
               "snow advances with absolute time")
        expect(hash(render(SceneWorld(weather: .snow, timeMode: .day), reduceMotion: true))
               == hash(render(SceneWorld(weather: .snow, timeMode: .day), at: now.addingTimeInterval(1), reduceMotion: true)),
               "reduce motion freezes clouds, water, birds and precipitation")
        let roomDay = render(SceneWorld(timeMode: .day), background: .room, reduceMotion: true)
        let roomNight = render(SceneWorld(timeMode: .night), background: .room, reduceMotion: true)
        let roomRain = render(SceneWorld(weather: .rain, timeMode: .night), background: .room, reduceMotion: true)
        let monitor = CGRect(x: 690, y: 555, width: 245, height: 147)
        expect(hash(roomDay, rect: monitor) == hash(roomNight, rect: monitor), "indoor night grading preserves native monitor information")
        expect(hash(roomNight, rect: monitor) == hash(roomRain, rect: monitor), "weather never rains onto native monitor information")
        expect(luminance(roomNight, x: 600, y: 750) < luminance(roomDay, x: 600, y: 750), "the room shares the outdoor night state")
        let floorNightRatio = RoomAssets.usesFlatForeground ? 0.8 : 0.5
        expect(luminance(roomNight, x: 376, y: 280) < luminance(roomDay, x: 376, y: 280) * floorNightRatio,
               "the floor follows night lighting without retaining baked daytime beams")
        let glassPoint = RoomAssets.usesFlatForeground ? CGPoint(x:250,y:725) : CGPoint(x:181,y:824)
        let mullionPoint = RoomAssets.usesFlatForeground ? CGPoint(x:190,y:725) : CGPoint(x:133,y:824)
        expect(WorldAtmosphere.windowGlassPath.contains(glassPoint), "weather clipping includes real window glass")
        expect(!WorldAtmosphere.windowGlassPath.contains(mullionPoint), "weather clipping excludes the main wooden mullion")
        expect(!WorldAtmosphere.windowGlassPath.contains(CGPoint(x: 500, y: 400)), "weather clipping excludes the room interior")
        save(roomDay, name: "room-day"); save(roomNight, name: "room-night"); save(roomRain, name: "room-rain-night")
        for size in [CGSize(width: 960, height: 640), CGSize(width: 1920, height: 1080),
                     CGSize(width: 2560, height: 1080), CGSize(width: 800, height: 1200)] {
            let image = render(SceneWorld(weather: .rain, timeMode: .night), size: size)
            let p = image.data!.assumingMemoryBound(to: UInt8.self)
            expect(p[3] == 255 && p[(image.width * image.height - 1) * 4 + 3] == 255,
                   "outdoors fills all corners without letterboxing at \(size)")
        }
        expect(SceneRenderer.hasUnderwaterAssets, "both original underwater scene plates load")
        let sea = SceneWorld(timeMode: .day, theme: .underwater)
        let encounter = Date(timeIntervalSinceReferenceDate: 797_760_000 + 18)
        let shallow = render(sea, background: .room, at: encounter)
        let deep = render(sea, at: encounter)
        expect(luminance(shallow, x: 350, y: 450) > 1.5 * luminance(deep, x: 350, y: 450),
               "the shallow water column is visibly brighter than the deep canyon")
        let reef = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                             bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        UnderwaterWorkplaceScene.draw(in: reef, bounds: CGRect(origin: .zero, size: size), deep: false,
                                      world: sea, at: encounter, reduceMotion: false)
        let formerDeck = CGRect(x: 520, y: 185, width: 300, height: 90)
        expect(hash(reef, rect: formerDeck) == hash(shallow, rect: formerDeck),
               "the former platform area is now open reef")
        let submarineArea = CGRect(x: 348, y: 729, width: 315, height: 120)
        let emptyReef = render(sea, background: .room, at: encounter, taskCount: 0)
        expect(hash(emptyReef, rect: submarineArea) != hash(shallow, rect: submarineArea),
               "a real task updates the floating session submarine")
        let taskInUpperRow = WorkplaceTask(id: "slot-6", title: "扩展会话", status: .running, slot: 5)
        expect(ShallowDiveScene.submarineSlots(for: []) == [0, 1, 2]
               && ShallowDiveScene.submarineSlots(for: [taskInUpperRow]) == [0, 1, 2, 5],
               "the three permanent submarines remain visible even with empty or sparse task slots")
        let hud = CGRect(x: 805, y: 876, width: 850, height: 60)
        let stableReef = render(sea, background: .room, at: encounter, reduceMotion: true)
        let completedReef = render(sea, background: .room, at: encounter, reduceMotion: true, completedToday: 8)
        let laterReef = render(sea, background: .room, at: encounter.addingTimeInterval(86_460), reduceMotion: true)
        expect(hash(stableReef, rect: hud) == hash(completedReef, rect: hud),
               "the shallow header no longer displays a progress counter")
        expect(hash(stableReef, rect: hud) != hash(laterReef, rect: hud),
               "the shallow clock and date update even with reduced motion")
        let clearInterior = CGRect(x: 1577, y: 817, width: 12, height: 8)
        expect(hash(reef, rect: clearInterior) == hash(shallow, rect: clearInterior),
               "the clock bubble leaves the reef visible between text and rim")
        let sampleBubble = CGRect(x: 1528, y: 800, width: 118, height: 118)
        var dimReef = sea
        dimReef.timeMode = .night
        expect(UnderwaterWorkplaceScene.shallowTextIsDark(behind: sampleBubble, in: size, world: sea, at: encounter)
               != UnderwaterWorkplaceScene.shallowTextIsDark(behind: sampleBubble, in: size, world: dimReef, at: encounter),
               "the shallow clock switches contrast between bright and dim water")
        let playing = SceneAction(kind: .playWithCat, startedAt: encounter.addingTimeInterval(-6))
        let playingReef = render(sea, background: .room, at: encounter, action: playing)
        let companions = CGRect(x: 550, y: 270, width: 690, height: 350)
        expect(hash(playingReef, rect: companions) != hash(shallow, rect: companions),
               "the manual interaction changes both companions' poses and positions")
        let patrol = render(sea, background: .room, at: encounter, reduceMotion: true, mode: .standing)
        let paddling = render(sea, background: .room, at: encounter, reduceMotion: true, mode: .slacking)
        expect(Set([stableReef, patrol, paddling].map { hash($0, rect: companions) }).count == 3,
               "floating, horizontal patrol, and paddling have distinct diver poses")
        let beforeRoll = SceneAction(kind: .playWithCat, startedAt: encounter.addingTimeInterval(-4))
        let sealArea = CGRect(x: 940, y: 295, width: 250, height: 230)
        expect(hash(render(sea, background: .room, at: encounter, action: beforeRoll), rect: sealArea)
               != hash(playingReef, rect: sealArea),
               "the seal rolls during the interaction")
        let tall = render(sea, background: .room, at: encounter, size: CGSize(width: 800, height: 1200), taskCount: 6)
        let tallTop = CGRect(x: 80, y: 870, width: 640, height: 210)
        let tallOne = render(sea, background: .room, at: encounter, size: CGSize(width: 800, height: 1200))
        expect(hash(tall, rect: tallTop) != hash(tallOne, rect: tallTop),
               "additional task submarines fit the shallow reef on a portrait screen")
        var darkSea = sea
        darkSea.timeMode = .night
        expect(hash(render(darkSea, at: encounter)) != hash(deep), "water lighting changes the rendered canyon")
        expect(hash(render(sea, at: encounter.addingTimeInterval(1))) != hash(deep),
               "the shared clock advances fish, current, and bubbles")
        let calm = render(sea, at: encounter, reduceMotion: true)
        expect(hash(render(sea, at: encounter.addingTimeInterval(1), reduceMotion: true)) == hash(calm),
               "underwater animations respect reduced motion")
        let notes = [
            PendingNote(id: "reef-check", text: "检查观测记录", createdAt: encounter.addingTimeInterval(-900), slot: 1),
            PendingNote(id: "dive-plan", text: "整理下次潜水计划", createdAt: encounter.addingTimeInterval(-1_260), slot: 3)
        ]
        let visitors = render(sea, at: encounter, notes: notes)
        expect(hash(visitors) != hash(deep), "deep sea renders visiting divers and their notes")
        let overdue = PendingNote(id: "reef-overdue", text: "检查海流传感器",
                                  createdAt: encounter.addingTimeInterval(-18_000), slot: 1)
        let storm = render(sea, at: encounter, notes: [overdue])
        let currentWater = CGRect(x: 600, y: 730, width: 440, height: 130)
        expect(hash(storm, rect: currentWater) == hash(deep, rect: currentWater),
               "an overdue note does not affect the independently selected water condition")
        let depthBadge = CGRect(x: 20, y: 18, width: 348, height: 44)
        expect(hash(storm, rect: depthBadge) != hash(deep, rect: depthBadge),
               "an overdue note is indicated in the depth badge")
        save(shallow, name: "underwater-shallow")
        save(visitors, name: "underwater-deep")
        print("PASS: \(checks) shared-world atmosphere, clipping, readability and rendering checks")
    }
}
