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
                       size: CGSize = size) -> CGContext {
        let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                          bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        var snapshot = SceneSnapshot.empty(now: date)
        snapshot.mode = .sitting; snapshot.world = world
        snapshot.tasks = [WorkplaceTask(id: "fixture", title: "共享世界渲染测试", status: .running, slot: 0)]
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
        print("PASS: \(checks) shared-world atmosphere, clipping, readability and rendering checks")
    }
}
