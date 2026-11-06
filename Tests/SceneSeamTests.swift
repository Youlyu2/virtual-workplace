import AppKit
import ImageIO
import Darwin

@main enum SceneSeamTests {
    private static var checks = 0
    private static let date = Date(timeIntervalSince1970: 1_793_661_610)
    private static let pairedDisplays = [
        DisplaySceneDescriptor(id: "seam-left", name: "Left", frame: CGRect(x: -1672, y: 0, width: 1672, height: 941), isMain: false),
        DisplaySceneDescriptor(id: "seam-main", name: "Main", frame: CGRect(x: 0, y: 0, width: 1672, height: 941), isMain: true)
    ]
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), "FAIL: \(message)")
    }

    private static func context(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func overlay(_ viewport: WorldViewport, world: SceneWorld,
                                at now: Date = date) -> CGContext {
        let result = context(viewport.display.size)
        SceneSeamBlend.draw(in: result, bounds: CGRect(origin: .zero, size: viewport.display.size),
            world: world, at: now, viewport: viewport)
        return result
    }

    private static func garden(_ viewport: WorldViewport, world: SceneWorld,
                               at now: Date = date, reduceMotion: Bool = true) -> CGContext {
        let result = context(viewport.display.size)
        OutdoorWorkplaceScene.drawGarden(in: result, bounds: CGRect(origin: .zero, size: viewport.display.size),
            world: world, at: now, reduceMotion: reduceMotion, viewport: viewport)
        return result
    }

    private static func alpha(_ c: CGContext, x: Int, y: Int) -> UInt8 {
        let offset = ((c.height - 1 - y) * c.width + x) * 4 + 3
        return c.data!.assumingMemoryBound(to: UInt8.self)[offset]
    }

    private static func checkSpriteAlpha() {
        let source = context(CGSize(width: 9, height: 9))
        func pixel(_ x: Int, _ y: Int, _ color: UInt32, alpha: CGFloat = 1) {
            source.setFillColor(WorldAtmosphere.color(color, alpha: alpha).cgColor)
            source.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
        source.setFillColor(WorldAtmosphere.color(0xCA6818).cgColor)
        source.fill(CGRect(x: 1, y: 1, width: 7, height: 7))
        pixel(1, 4, 0x00FF00) // A matte key at the transparent outside edge.
        pixel(2, 4, 0xFF0000) // Connected key color inside that same matte spill.
        pixel(4, 4, 0xFF0000) // Isolated authored red must survive.
        pixel(1, 6, 0xD53F9A) // Flower color is not a matte key.
        pixel(7, 6, 0x73A526) // Saturated natural foliage must survive.
        source.clear(CGRect(x: 1, y: 2, width: 1, height: 1))
        pixel(1, 2, 0xFF0000, alpha: 0.02)
        source.clear(CGRect(x: 5, y: 6, width: 1, height: 1))
        pixel(5, 6, 0xCFBA90, alpha: 0.99)
        let cleaned = context(CGSize(width: 9, height: 9))
        cleaned.draw(PixelAssetTransparency.cleaned(source.makeImage()!)!, in: CGRect(x: 0, y: 0, width: 9, height: 9))
        expect(alpha(cleaned, x: 1, y: 4) == 0 && alpha(cleaned, x: 2, y: 4) == 0,
            "only matte keys connected to transparency are removed")
        expect(alpha(cleaned, x: 4, y: 4) == 255 && alpha(cleaned, x: 1, y: 6) == 255
               && alpha(cleaned, x: 7, y: 6) == 255 && alpha(cleaned, x: 1, y: 3) == 255,
            "isolated authored red, pink flowers, green leaves and warm timber remain opaque")
        expect(alpha(cleaned, x: 1, y: 2) == 0 && alpha(cleaned, x: 5, y: 6) == 255,
            "export residue clears while near-opaque floor pixels become fully opaque")
    }

    private static func alphaCount(_ c: CGContext, rect: CGRect? = nil) -> Int {
        let r = (rect ?? CGRect(x: 0, y: 0, width: c.width, height: c.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: c.width, height: c.height))
        guard !r.isNull else { return 0 }
        var result = 0
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) where alpha(c, x: x, y: y) > 0 { result += 1 }
        }
        return result
    }

    private static func cropMatches(_ part: CGContext, whole: CGContext, offset: CGPoint) -> Bool {
        let source = whole.data!, target = part.data!
        let sourceTopRow = whole.height - part.height - Int(offset.y)
        for row in 0..<part.height {
            let sourceOffset = (sourceTopRow + row) * whole.bytesPerRow + Int(offset.x) * 4
            if memcmp(source.advanced(by: sourceOffset), target.advanced(by: row * part.bytesPerRow), part.width * 4) != 0 { return false }
        }
        return true
    }

    private static func identical(_ first: CGContext, _ second: CGContext) -> Bool {
        first.width == second.width && first.height == second.height
            && memcmp(first.data!, second.data!, first.bytesPerRow * first.height) == 0
    }

    private static func identical(_ first: CGContext, _ second: CGContext, in rect: CGRect) -> Bool {
        guard first.width == second.width, first.height == second.height else { return false }
        for y in Int(rect.minY)..<Int(rect.maxY) {
            let start = (first.height - 1 - y) * first.bytesPerRow + Int(rect.minX) * 4
            if memcmp(first.data!.advanced(by: start), second.data!.advanced(by: start), Int(rect.width) * 4) != 0 {
                return false
            }
        }
        return true
    }

    private static func emptyAreasStayEmpty(_ reference: CGContext, _ variant: CGContext) -> Bool {
        let a = reference.data!.assumingMemoryBound(to: UInt8.self)
        let b = variant.data!.assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 3, to: reference.bytesPerRow * reference.height, by: 4)
            where a[offset] == 0 && b[offset] != 0 { return false }
        return true
    }

    private static func mirroredMatches(_ reference: CGContext, _ mirrored: CGContext) -> Bool {
        let a = reference.data!.assumingMemoryBound(to: UInt8.self)
        let b = mirrored.data!.assumingMemoryBound(to: UInt8.self)
        for row in 0..<reference.height {
            for x in 0..<reference.width {
                let first = row * reference.bytesPerRow + x * 4
                let second = row * mirrored.bytesPerRow + (reference.width - 1 - x) * 4
                if memcmp(a.advanced(by: first), b.advanced(by: second), 4) != 0 { return false }
            }
        }
        return true
    }

    private static func save(_ c: CGContext, _ name: String) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/seam-review")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = CGImageDestinationCreateWithURL(root.appendingPathComponent(name + ".png") as CFURL,
            "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, c.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }

    private static func scene(_ viewport: WorldViewport, background: WorkplaceBackground,
                              world: SceneWorld, at now: Date) -> CGContext {
        let c = context(viewport.display.size)
        var snapshot = SceneSnapshot.empty(now: now)
        snapshot.mode = .sitting; snapshot.taskOrigin = .simulation; snapshot.world = world
        snapshot.world?.weatherMode = .manual
        snapshot.tasks = [WorkplaceTask(id: "seam-fixture", title: "检查场景衔接", status: .running, slot: 0)]
        SceneRenderer.draw(in: c, bounds: CGRect(origin: .zero, size: viewport.display.size),
            snapshot: snapshot, time: 0, reduceMotion: true, now: now, background: background, viewport: viewport)
        return c
    }

    private static func renderPair(world: SceneWorld, name: String) {
        let now = Date()
        let result = context(CGSize(width: 3344, height: 941))
        var snapshot = SceneSnapshot.empty(now: now)
        snapshot.mode = .sitting; snapshot.taskOrigin = .simulation; snapshot.world = world
        snapshot.world?.weatherMode = .manual
        for (index, display) in pairedDisplays.enumerated() {
            let background = DisplaySceneRouting.background(for: display, among: pairedDisplays,
                world: world, context: .screenSaver)
            let viewport = DisplaySceneRouting.viewport(for: display, among: pairedDisplays,
                world: world, context: .screenSaver)!
            let bounds = CGRect(x: CGFloat(index) * 1672, y: 0, width: 1672, height: 941)
            result.saveGState(); result.clip(to: bounds)
            SceneRenderer.draw(in: result, bounds: bounds, snapshot: snapshot, time: 0,
                reduceMotion: true, now: now, background: background, viewport: viewport)
            result.restoreGState()
        }
        save(result, name)
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        checkSpriteAlpha()
        expect(SceneSeamBlend.isAvailable, "the native flat threshold is available without a vine sprite")
        expect(RoomAssets.gardenForeground != nil, "the separate flat garden foreground is packaged")

        let left = CGRect(x: -1672, y: 0, width: 1672, height: 941)
        let right = CGRect(x: 0, y: 0, width: 1672, height: 941)
        let canvas = left.union(right)
        let seam = WorldSeam(boundaryX: 0, lowerY: 0, upperY: 941, roomOnRight: true)
        let full = WorldViewport(canvas: canvas, display: canvas, seams: [seam])!
        let split = pairedDisplays.map {
            DisplaySceneRouting.viewport(for: $0, among: pairedDisplays, context: .screenSaver)!
        }
        for (index, display) in pairedDisplays.enumerated() {
            let desktop = DisplaySceneRouting.viewport(for: display, among: pairedDisplays)!
            expect(DisplaySceneRouting.background(for: display, among: pairedDisplays, world: SceneWorld()) == .room
                   && desktop.seams.isEmpty && alphaCount(overlay(desktop, world: SceneWorld())) == 0,
                "the production desktop room pair has no exterior seam artwork")
            expect(split[index].seams == [seam] && split[index].canvas == desktop.canvas
                   && split[index].display == desktop.display,
                "the saver selects a shared exterior seam without changing the physical desktop camera")
        }
        let worlds = [SceneWorld(timeMode: .day), SceneWorld(timeMode: .night),
                      SceneWorld(weather: .rain, timeMode: .night), SceneWorld(weather: .snow, timeMode: .sunset)]
        for world in worlds {
            let whole = overlay(full, world: world)
            expect(alphaCount(whole) > 1000, "\(world.weather)/\(world.timeMode) foreground is visible")
            for camera in split {
                let part = overlay(camera, world: world)
                expect(cropMatches(part, whole: whole, offset: CGPoint(x: camera.display.minX - canvas.minX, y: 0)),
                    "\(world.weather)/\(world.timeMode) independently drawn screen keeps an exact seam foreground crop")
            }
            let roomOnly = overlay(split[1], world: world)
            expect(alphaCount(roomOnly, rect: CGRect(x: 42, y: 0, width: 1630, height: 941)) == 0,
                "\(world.weather)/\(world.timeMode) decoration and shadow cannot reach window glass or task panels")
            let wholeGarden = garden(full, world: world)
            expect(alphaCount(wholeGarden, rect: CGRect(x: 1672, y: 0, width: 1672, height: 941)) == 0,
                "the garden foreground never paints inside the room")
            expect(cropMatches(garden(split[0], world: world), whole: wholeGarden, offset: .zero),
                "\(world.weather)/\(world.timeMode) the garden has an exact shared-world crop")
            expect(alpha(wholeGarden, x: 1660, y: 165) == 255,
                "the near path reaches the flat doorway height with an opaque floor")
        }

        let plain = WorldViewport(canvas: canvas, display: canvas)!
        expect(alphaCount(overlay(plain, world: worlds[0])) == 0, "no room/outdoor boundary creates no decorative overlay")
        let untouched = context(canvas.size)
        untouched.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8))
        untouched.fill(CGRect(origin: .zero, size: canvas.size))
        let before = context(canvas.size)
        before.draw(untouched.makeImage()!, in: CGRect(origin: .zero, size: canvas.size))
        SceneSeamBlend.draw(in: untouched, bounds: CGRect(origin: .zero, size: canvas.size),
            world: worlds[0], at: date, viewport: plain)
        expect(identical(before, untouched), "a no-seam renderer leaves existing scene pixels unchanged")
        let day = overlay(full, world: worlds[0]), night = overlay(full, world: worlds[1])
        let threshold = CGRect(x: 1672 - SceneSeamBlend.thresholdWidth / 2,
            y: SceneSeamBlend.passageRange.lowerBound, width: SceneSeamBlend.thresholdWidth,
            height: SceneSeamBlend.passageRange.upperBound - SceneSeamBlend.passageRange.lowerBound)
        expect(alphaCount(day) == Int(threshold.width * threshold.height),
            "the two-dimensional threshold contains only its flat ground footprint")
        expect(alphaCount(day, rect: CGRect(x: 1500, y: 220, width: 344, height: 721)) == 0,
            "no ivy, vertical doorpost, stair riser or shadow crosses above the flat passage")
        expect(!identical(day, night), "foreground lighting follows the shared day/night state")
        for world in worlds.dropFirst() {
            expect(emptyAreasStayEmpty(day, overlay(full, world: world)),
                "\(world.weather)/\(world.timeMode) lighting cannot paint transparent sprite holes")
        }
        expect(identical(day, overlay(full, world: worlds[0], at: date.addingTimeInterval(1))),
            "a static foreground adds no independent animation clock")
        expect(!identical(garden(full, world: worlds[0]), garden(full, world: worlds[1])),
            "the flat garden follows the same day/night state as the mountains")
        expect(identical(garden(full, world: worlds[2]),
                         garden(full, world: worlds[2], at: date.addingTimeInterval(1))),
            "reduce motion freezes foreground precipitation using the shared clock")
        expect(alphaCount(day, rect: CGRect(x: 0, y: 0, width: 1100, height: 941)) == 0,
            "the center of the outdoor landscape stays untouched")

        let mirror = WorldSeam(boundaryX: 0, lowerY: 0, upperY: 941, roomOnRight: false)
        let mirrored = overlay(WorldViewport(canvas: canvas, display: canvas, seams: [mirror])!, world: worlds[0])
        expect(alphaCount(mirrored) > 1000, "a room on the left receives a mirrored transition")
        expect(mirroredMatches(day, mirrored), "a left-hand room receives the exact horizontal reflection of the right-hand transition")
        expect(mirroredMatches(garden(full, world: worlds[0]),
            garden(WorldViewport(canvas: canvas, display: canvas, seams: [mirror])!, world: worlds[0])),
            "the right-hand garden uses the same flat plane reflected across the room seam")
        expect(alphaCount(mirrored, rect: CGRect(x: 0, y: 0, width: 1630, height: 941)) == 0,
            "the mirrored transition also preserves the room's deep interior")

        let raised = CGRect(x: -800, y: 90, width: 800, height: 450)
        let larger = CGRect(x: 0, y: 0, width: 960, height: 540)
        let offsetCanvas = raised.union(larger)
        let partial = WorldSeam(boundaryX: 0, lowerY: 90, upperY: 540, roomOnRight: true)
        let offsetWhole = overlay(WorldViewport(canvas: offsetCanvas, display: offsetCanvas, seams: [partial])!, world: worlds[2])
        for display in [raised, larger] {
            let part = overlay(WorldViewport(canvas: offsetCanvas, display: display, seams: [partial])!, world: worlds[2])
            expect(cropMatches(part, whole: offsetWhole,
                offset: CGPoint(x: display.minX - offsetCanvas.minX, y: display.minY - offsetCanvas.minY)),
                "a raised or different-sized monitor retains the same foreground crop")
        }
        let offsetGarden = garden(WorldViewport(canvas: offsetCanvas, display: offsetCanvas, seams: [partial])!, world: worlds[2])
        expect(cropMatches(garden(WorldViewport(canvas: offsetCanvas, display: raised, seams: [partial])!, world: worlds[2]),
            whole: offsetGarden, offset: CGPoint(x: 0, y: 90)),
            "a raised outdoor monitor retains its world-anchored flat path")

        let ultraWide = CGRect(x: -2400, y: 0, width: 2400, height: 941)
        let wideCanvas = ultraWide.union(right)
        let wideCamera = WorldViewport(canvas: wideCanvas, display: ultraWide, seams: [seam])!
        let wholeWideCamera = WorldViewport(canvas: wideCanvas, display: wideCanvas, seams: [seam])!
        let extensionGround = CGRect(x: 32, y: 16, width: 640, height: 340)
        for weather in [WorldWeather.rain, .snow] {
            let world = SceneWorld(weather: weather, timeMode: .day)
            let first = garden(wideCamera, world: world, reduceMotion: false)
            let next = garden(wideCamera, world: world, at: date.addingTimeInterval(1), reduceMotion: false)
            expect(!identical(first, next, in: extensionGround),
                "\(weather) particles also advance over the ultra-wide garden extension")
            expect(cropMatches(first, whole: garden(wholeWideCamera, world: world, reduceMotion: false), offset: .zero),
                "\(weather) extension tiles preserve the same full-world precipitation phase")
            let frozen = garden(wideCamera, world: world)
            let frozenLater = garden(wideCamera, world: world, at: date.addingTimeInterval(1))
            expect(identical(frozen, frozenLater, in: extensionGround),
                "reduce motion freezes \(weather) on the ultra-wide extension as well")
        }

        let visibleDate = Date()
        let roomWith = scene(split[1], background: .room, world: worlds[0], at: visibleDate)
        let roomWithout = scene(WorldViewport(canvas: canvas, display: right)!, background: .room, world: worlds[0], at: visibleDate)
        for rect in [CGRect(x: 675, y: 545, width: 280, height: 176),
                     CGRect(x: 42, y: 553, width: 278, height: 356)] {
            let a = roomWith.data!, b = roomWithout.data!
            var matches = true
            for y in Int(rect.minY)..<Int(rect.maxY) {
                let start = ((roomWith.height - 1 - y) * roomWith.width + Int(rect.minX)) * 4
                if memcmp(a.advanced(by: start), b.advanced(by: start), Int(rect.width) * 4) != 0 { matches = false }
            }
            expect(matches, "foreground addition preserves the complete task monitor and window glass region")
        }

        save(day, "overlay-day"); save(night, "overlay-night"); save(mirrored, "overlay-mirrored")
        renderPair(world: SceneWorld(timeMode: .day), name: "pair-day")
        renderPair(world: SceneWorld(timeMode: .night), name: "pair-night")
        print("PASS: \(checks) flat threshold footprint, shared crop, light and room-protection checks")
    }
}
