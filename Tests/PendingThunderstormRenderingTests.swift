import AppKit
import ImageIO
import Darwin

@main enum PendingThunderstormRenderingTests {
    private static var checks = 0
    private static let size = CGSize(width: 1672, height: 941)
    private static let referenceDate = Date(timeIntervalSince1970: 1_794_006_000)
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), "FAIL: \(message)")
    }
    private static func context(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func same(_ a: CGContext, _ b: CGContext, rect: CGRect? = nil) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        let area = rect ?? CGRect(x: 0, y: 0, width: a.width, height: a.height)
        for y in Int(area.minY)..<Int(area.maxY) {
            let start = (a.height - 1 - y) * a.bytesPerRow + Int(area.minX) * 4
            if memcmp(a.data!.advanced(by: start), b.data!.advanced(by: start), Int(area.width) * 4) != 0 { return false }
        }
        return true
    }
    private static func alphaCount(_ c: CGContext) -> Int {
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: c.height * c.bytesPerRow, by: 4).reduce(0) { $0 + (p[$1] > 0 ? 1 : 0) }
    }
    private static func lightning(_ now: Date, reduce: Bool = false) -> CGContext {
        let c = context(size)
        WorldAtmosphere.lightning(in: c, canvas: CGRect(origin: .zero, size: size),
            weather: .thunderstorm, at: now, reduceMotion: reduce)
        return c
    }
    private static func backdrop(_ viewport: WorldViewport, at now: Date, reduce: Bool = false) -> CGContext {
        let c = context(viewport.display.size)
        OutdoorWorkplaceScene.drawBackdrop(in: c, bounds: CGRect(origin: .zero, size: viewport.display.size),
            world: SceneWorld(weather: .thunderstorm, timeMode: .night), at: now,
            reduceMotion: reduce, viewport: viewport)
        return c
    }
    private static func cropMatches(_ part: CGContext, _ full: CGContext, x: Int) -> Bool {
        for row in 0..<part.height {
            if memcmp(part.data!.advanced(by: row * part.bytesPerRow),
                full.data!.advanced(by: row * full.bytesPerRow + x * 4), part.bytesPerRow) != 0 { return false }
        }
        return true
    }
    private static func scene(_ now: Date, background: WorkplaceBackground, mode: WorldTimeMode,
                              reduce: Bool = false, uptime: TimeInterval = 0) -> CGContext {
        let c = context(size)
        var snapshot = SceneSnapshot.empty(now: now)
        snapshot.mode = .sitting; snapshot.world = SceneWorld(weather: .thunderstorm, timeMode: mode)
        snapshot.tasks = [WorkplaceTask(id: "storm-monitor", title: "确认任务信息保持清晰", status: .running, slot: 0)]
        SceneRenderer.draw(in: c, bounds: CGRect(origin: .zero, size: size), snapshot: snapshot,
            time: uptime, reduceMotion: reduce, now: now, background: background)
        return c
    }
    private static func save(_ c: CGContext, _ name: String) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/thunderstorm-review")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = CGImageDestinationCreateWithURL(root.appendingPathComponent(name + ".png") as CFURL,
            "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, c.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }

    static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let firstIndex = Int(floor(referenceDate.timeIntervalSinceReferenceDate / 35))
        var outsideFlash: Date?, roomFlash: Date?
        for index in firstIndex..<(firstIndex + 500) {
            let start = WorldAtmosphere.lightningEventTime(index: index)
            let gap = WorldAtmosphere.lightningEventTime(index: index + 1) - start
            expect((25...45).contains(gap), "neighboring lightning events stay 25–45 seconds apart")
            let peak = Date(timeIntervalSinceReferenceDate: start + 0.12)
            let sample = WorldAtmosphere.lightningSample(at: peak, weather: .thunderstorm, reduceMotion: false)!
            expect(sample.intensity > 0.99 && sample.intensity <= 1 && (0.18...0.84).contains(sample.xFraction),
                "the shared lightning sample has bounded intensity and in-frame position")
            expect(WorldAtmosphere.lightningSample(at: peak, weather: .thunderstorm, reduceMotion: true) == nil,
                "reduce motion suppresses lightning entirely")
            expect(WorldAtmosphere.lightningSample(at: peak, weather: .rain, reduceMotion: false) == nil,
                "ordinary rain never flashes")
            let minutePosition = WorldAtmosphere.positiveRemainder(start, 60)
            if (4...54).contains(minutePosition) {
                if outsideFlash == nil && (0.26...0.38).contains(sample.xFraction) { outsideFlash = peak }
                if roomFlash == nil && (0.555...0.58).contains(sample.xFraction) { roomFlash = peak }
            }
        }
        expect(outsideFlash != nil && roomFlash != nil, "fixtures include a visible outdoor bolt and a bolt behind the room glass")
        let now = outsideFlash!, windowDate = roomFlash!
        let current = WorldAtmosphere.lightningSample(at: now, weather: .thunderstorm, reduceMotion: false)!
        let start = WorldAtmosphere.lightningEventTime(index: current.eventIndex)
        expect(WorldAtmosphere.lightningSample(at: Date(timeIntervalSinceReferenceDate: start - 0.01),
            weather: .thunderstorm, reduceMotion: false) == nil, "no lightning appears before its event")
        expect(WorldAtmosphere.lightningSample(at: Date(timeIntervalSinceReferenceDate: start + 0.81),
            weather: .thunderstorm, reduceMotion: false) == nil, "the soft lightning pulse ends in under a second")
        for time in [TimeInterval.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            expect(WorldAtmosphere.lightningSample(at: Date(timeIntervalSinceReferenceDate: time),
                weather: .thunderstorm, reduceMotion: false) == nil, "invalid diagnostic clocks cannot create a flash or overflow")
        }
        let layer = lightning(now), bytes = layer.data!.assumingMemoryBound(to: UInt8.self)
        let region = WorldAtmosphere.lightningRegion(in: CGRect(origin: .zero, size: size))
        var maximumAlpha: UInt8 = 0, outsideInk = 0
        for row in 0..<layer.height {
            for x in 0..<layer.width {
                let alpha = bytes[(row * layer.width + x) * 4 + 3]
                maximumAlpha = max(maximumAlpha, alpha)
                if alpha > 0 && !region.contains(CGPoint(x: x, y: layer.height - 1 - row)) { outsideInk += 1 }
            }
        }
        expect(alphaCount(layer) > 300 && alphaCount(layer) < layer.width * layer.height / 25,
            "lightning covers a small local footprint rather than flashing the full screen")
        expect(outsideInk == 0, "the lightning mask excludes the entire near garden and visitor band")
        expect(maximumAlpha <= 160, "overlapping bolt segments never accumulate into a fully bright flash")
        expect(alphaCount(lightning(now, reduce: true)) == 0, "reduced motion draws no lightning pixels")
        expect(same(lightning(now), lightning(now)), "separate hosts sample the same absolute lightning frame")

        let weatherRect = CGRect(origin: .zero, size: size)
        let rain = context(size), storm = context(size)
        WorldAtmosphere.precipitation(in: rain, rect: weatherRect, weather: .rain, time: 0, reduceMotion: true)
        WorldAtmosphere.precipitation(in: storm, rect: weatherRect, weather: .thunderstorm, time: 0, reduceMotion: true)
        expect(alphaCount(storm) > alphaCount(rain), "thunderstorm has denser static precipitation than ordinary rain")
        let gardenA = context(size), gardenB = context(size)
        let world = SceneWorld(weather: .thunderstorm, timeMode: .night)
        for (c, date) in [(gardenA, now), (gardenB, now.addingTimeInterval(1))] {
            OutdoorWorkplaceScene.drawGarden(in: c, bounds: weatherRect, world: world,
                at: date, reduceMotion: true, viewport: .companion(for: .outdoors))
        }
        expect(same(gardenA, gardenB), "the foreground repaint adds static storm rain without a second flash")
        let left = CGRect(x: -1672, y: 0, width: 1672, height: 941)
        let right = CGRect(x: 0, y: 0, width: 1672, height: 941), canvas = left.union(right)
        let full = backdrop(WorldViewport(canvas: canvas, display: canvas)!, at: now)
        expect(cropMatches(backdrop(WorldViewport(canvas: canvas, display: left)!, at: now), full, x: 0)
               && cropMatches(backdrop(WorldViewport(canvas: canvas, display: right)!, at: now), full, x: 1672),
            "independent displays share the exact world-space lightning and precipitation crop")
        expect(same(backdrop(.companion(for: .outdoors), at: now, reduce: true),
                    backdrop(.companion(for: .outdoors), at: now.addingTimeInterval(1), reduce: true)),
            "reduced motion freezes clouds and rain while lightning remains disabled")

        let roomActive = scene(windowDate, background: .room, mode: .night)
        let roomAfter = scene(windowDate.addingTimeInterval(0.9), background: .room, mode: .night)
        let mask = context(size); mask.saveGState(); WindowGlassMask.clip(in: mask)
        mask.setFillColor(NSColor.white.cgColor); mask.fill(weatherRect); mask.restoreGState()
        let glass = mask.data!.assumingMemoryBound(to: UInt8.self)
        let a = roomActive.data!.assumingMemoryBound(to: UInt8.self)
        let b = roomAfter.data!.assumingMemoryBound(to: UInt8.self)
        var outsideChanges = 0, glassChanges = 0
        for offset in stride(from: 0, to: roomActive.height * roomActive.bytesPerRow, by: 4) {
            if memcmp(a.advanced(by: offset), b.advanced(by: offset), 4) != 0 {
                if glass[offset + 3] == 0 { outsideChanges += 1 } else { glassChanges += 1 }
            }
        }
        expect(glassChanges > 0 && outsideChanges == 0,
            "actual room storm motion changes only glass pixels, never walls, floor, task screens or overlays")
        expect(same(roomActive, roomAfter, rect: CGRect(x: 690, y: 555, width: 245, height: 147)),
            "native task text is unchanged during a lightning pulse")
        expect(same(scene(now, background: .outdoors, mode: .night, uptime: 0),
                    scene(now, background: .outdoors, mode: .night, uptime: 99_999)),
            "screen saver and app host uptime cannot change thunderstorm phase")
        save(scene(now, background: .outdoors, mode: .day), "thunderstorm-day-lightning")
        save(scene(now, background: .outdoors, mode: .night), "thunderstorm-night-lightning")
        save(scene(now, background: .outdoors, mode: .day, reduce: true), "thunderstorm-reduced-motion")
        save(roomActive, "room-night-window-lightning"); save(layer, "lightning-local-alpha")
        print("PASS: \(checks) shared thunderstorm phase, bounded light, clipping and reduced-motion checks")
        print("PREVIEWS: build/thunderstorm-review")
    }
}
