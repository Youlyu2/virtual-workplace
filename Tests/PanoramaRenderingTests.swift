import AppKit
import ImageIO

@main enum PanoramaRenderingTests {
    static var checks = 0
    static let date = Date(timeIntervalSince1970: 1_793_661_610)
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), "FAIL: \(message)")
    }
    static func context(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    static func backdrop(_ viewport: WorldViewport, world: SceneWorld, reduceMotion: Bool = false,
                         at now: Date = date) -> CGContext {
        let c = context(viewport.display.size)
        OutdoorWorkplaceScene.drawBackdrop(in: c, bounds: CGRect(origin: .zero, size: viewport.display.size),
            world: world, at: now, reduceMotion: reduceMotion, viewport: viewport)
        return c
    }
    static func rgba(_ c: CGContext, x: Int, y: Int) -> [UInt8] {
        let offset = ((c.height - 1 - y) * c.width + x) * 4
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { p[offset + $0] }
    }
    static func matchingCrop(_ part: CGContext, full: CGContext, offset: CGPoint) -> Bool {
        let p = part.data!.assumingMemoryBound(to: UInt8.self)
        let f = full.data!.assumingMemoryBound(to: UInt8.self)
        let x0 = Int(offset.x), y0 = Int(offset.y)
        for y in 0..<part.height {
            let source = ((full.height - 1 - (y0 + y)) * full.width + x0) * 4
            let target = ((part.height - 1 - y) * part.width) * 4
            for column in 0..<(part.width * 4) where p[target + column] != f[source + column] { return false }
        }
        return true
    }
    static func save(_ image: CGContext, name: String) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/alignment")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(name + ".png")
        let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    static func main() {
        _ = NSApplication.shared
        expect(RoomAssets.panorama != nil, "the shared panoramic landscape asset is present")
        expect(RoomAssets.windowForeground != nil && WindowGlassMask.usesArtworkMask,
               "the selected room plate uses its matching authored glass alpha")
        let left = CGRect(x: -960, y: 0, width: 960, height: 540)
        let room = CGRect(x: 0, y: 0, width: 960, height: 540)
        let canvas = left.union(room)
        let full = WorldViewport(canvas: canvas, display: canvas)!
        let cameras = [WorldViewport(canvas: canvas, display: left)!, WorldViewport(canvas: canvas, display: room)!]
        let cases: [SceneWorld] = [SceneWorld(timeMode: .day), SceneWorld(timeMode: .night),
            SceneWorld(weather: .rain, timeMode: .night), SceneWorld(weather: .snow, timeMode: .sunset)]
        for world in cases {
            let whole = backdrop(full, world: world)
            for camera in cameras {
                let slice = backdrop(camera, world: world)
                expect(matchingCrop(slice, full: whole,
                    offset: CGPoint(x: camera.display.minX - canvas.minX, y: camera.display.minY - canvas.minY)),
                    "\(world.weather)/\(world.timeMode) screen is an exact crop of the one panorama")
            }
        }
        let raised = CGRect(x: -800, y: 90, width: 800, height: 450)
        let larger = CGRect(x: 0, y: 0, width: 960, height: 540)
        let offsetCanvas = raised.union(larger)
        let offsetFull = backdrop(WorldViewport(canvas: offsetCanvas, display: offsetCanvas)!,
                                  world: SceneWorld(weather: .rain, timeMode: .day))
        for frame in [raised, larger] {
            let slice = backdrop(WorldViewport(canvas: offsetCanvas, display: frame)!,
                                 world: SceneWorld(weather: .rain, timeMode: .day))
            expect(matchingCrop(slice, full: offsetFull,
                offset: CGPoint(x: frame.minX - offsetCanvas.minX, y: frame.minY - offsetCanvas.minY)),
                "different-sized and vertically offset physical displays retain their world origin")
        }

        let roomCamera = WorldViewport.companion(for: .room)
        let roomSize = roomCamera.display.size
        let mask = context(roomSize)
        mask.saveGState(); WindowGlassMask.clip(in: mask)
        mask.setFillColor(NSColor.white.cgColor); mask.fill(CGRect(origin: .zero, size: roomSize)); mask.restoreGState()
        for world in cases {
            let outside = backdrop(roomCamera, world: world)
            let inside = context(roomSize)
            var snapshot = SceneSnapshot.empty(now: date)
            snapshot.mode = .sitting; snapshot.world = world
            snapshot.world?.weatherMode = .manual
            SceneRenderer.draw(in: inside, bounds: CGRect(origin: .zero, size: roomSize), snapshot: snapshot,
                time: 0, reduceMotion: false, now: date, background: .room, viewport: roomCamera)
            var glassSamples = 0, matches = true
            for y in Int(WindowGlassMask.bounds.minY)..<Int(WindowGlassMask.bounds.maxY) {
                for x in Int(WindowGlassMask.bounds.minX)..<Int(WindowGlassMask.bounds.maxX) where rgba(mask, x: x, y: y)[3] == 255 {
                    glassSamples += 1
                    if rgba(inside, x: x, y: y) != rgba(outside, x: x, y: y) { matches = false }
                }
            }
            expect(glassSamples > 1000, "glass comparison covers actual visible panes")
            expect(matches, "\(world.weather)/\(world.timeMode) room glass has exactly the adjacent world camera pixels")
        }
        let frozenA = backdrop(cameras[0], world: SceneWorld(weather: .snow, timeMode: .night), reduceMotion: true)
        let frozenB = backdrop(cameras[0], world: SceneWorld(weather: .snow, timeMode: .night),
                               reduceMotion: true, at: date.addingTimeInterval(1))
        expect(matchingCrop(frozenA, full: frozenB, offset: .zero), "reduce motion freezes the whole panorama consistently")

        let pair = context(CGSize(width: 3344, height: 941))
        for (index, background) in [WorkplaceBackground.outdoors, .room].enumerated() {
            let bounds = CGRect(x: CGFloat(index) * 1672, y: 0, width: 1672, height: 941)
            var snapshot = SceneSnapshot.empty(now: date)
            snapshot.mode = .sitting; snapshot.world = SceneWorld(timeMode: .day)
            pair.saveGState(); pair.clip(to: bounds)
            SceneRenderer.draw(in: pair, bounds: bounds, snapshot: snapshot, time: 0,
                reduceMotion: true, now: date, background: background,
                viewport: .companion(for: background))
            pair.restoreGState()
        }
        save(pair, name: "shared-panorama-pair")
        print("PASS: \(checks) panoramic screen crops, physical offsets and exact room-window world continuity checks")
    }
}
