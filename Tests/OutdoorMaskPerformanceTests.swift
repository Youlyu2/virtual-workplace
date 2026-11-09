import AppKit
import CryptoKit
import Darwin

/// Synthetic renderer checks. No windows, user snapshots or live observers.
@main enum OutdoorMaskPerformanceTests {
    static let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    static let date = Date(timeIntervalSince1970: 1_793_661_610)
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ reason: String) {
        checks += 1
        if !value() { fputs("FAIL: \(reason)\n", stderr); exit(1) }
    }
    static func bitmap(width: Int = 1920, height: Int = 1080) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    static var cameras: [(String, WorldViewport)] {
        let room = CGRect(x: 0, y: 0, width: 1672, height: 941)
        let wide = CGRect(x: -2600, y: 0, width: 2600, height: 941)
        let mirrored = CGRect(x: 1672, y: 0, width: 2600, height: 941)
        let raised = CGRect(x: -1672, y: 120, width: 1672, height: 941)
        return [("normal", .companion(for: .outdoors)),
            ("wide-edge", WorldViewport(canvas: wide.union(room), display: wide,
                seams: [WorldSeam(boundaryX: 0, lowerY: 0, upperY: 941, roomOnRight: true)])!),
            ("mirrored-edge", WorldViewport(canvas: room.union(mirrored), display: mirrored,
                seams: [WorldSeam(boundaryX: 1672, lowerY: 0, upperY: 941, roomOnRight: false)])!),
            ("offset", WorldViewport(canvas: room.union(raised), display: raised,
                seams: [WorldSeam(boundaryX: 0, lowerY: 120, upperY: 941, roomOnRight: true)])!)]
    }
    static func hash(_ context: CGContext) -> String {
        let bytes = Data(bytesNoCopy: context.data!, count: context.bytesPerRow * context.height, deallocator: .none)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func hashes() -> [String: String] {
        let c = bitmap()
        var result: [String: String] = [:]
        for weather in WorldWeather.allCases {
            for mode in [WorldTimeMode.day, .sunset, .night] {
                let world = SceneWorld(weather: weather, weatherMode: .manual, timeMode: mode)
                for (name, camera) in cameras {
                    for gardenOnly in [false, true] {
                        autoreleasepool {
                            c.clear(bounds)
                            if gardenOnly {
                                OutdoorWorkplaceScene.drawGarden(in: c, bounds: bounds, world: world,
                                    at: date, reduceMotion: false, viewport: camera)
                            } else {
                                OutdoorWorkplaceScene.drawBackdrop(in: c, bounds: bounds, world: world,
                                    at: date, reduceMotion: false, viewport: camera)
                            }
                            result["\(weather.rawValue)-\(mode.rawValue)-\(name)-\(gardenOnly ? "garden" : "backdrop")"] = hash(c)
                        }
                    }
                }
            }
        }
        return result
    }
    static func gardenEquivalence() {
        for retina in [false, true] {
            let multiplier = retina ? 2 : 1
            let original = bitmap(width: 1920 * multiplier, height: 1080 * multiplier)
            let optimized = bitmap(width: 1920 * multiplier, height: 1080 * multiplier)
            original.scaleBy(x: CGFloat(multiplier), y: CGFloat(multiplier))
            optimized.scaleBy(x: CGFloat(multiplier), y: CGFloat(multiplier))
            let weathers: [WorldWeather] = retina ? [.clear, .rain] : WorldWeather.allCases
            let modes: [WorldTimeMode] = retina ? [.day, .night] : [.day, .sunset, .night]
            let selectedCameras = retina ? Array(cameras.prefix(3)) : cameras
            for weather in weathers { for mode in modes { for (name, camera) in selectedCameras {
                autoreleasepool {
                    let world = SceneWorld(weather: weather, weatherMode: .manual, timeMode: mode)
                    original.clear(bounds); optimized.clear(bounds)
                    LegacyGardenReference.draw(in: original, bounds: bounds, world: world,
                        at: date, reduceMotion: false, viewport: camera)
                    OutdoorWorkplaceScene.drawGarden(in: optimized, bounds: bounds, world: world,
                        at: date, reduceMotion: false, viewport: camera)
                    expect(hash(original) == hash(optimized),
                           "garden pixels must match former algorithm exactly: \(weather)/\(mode)/\(name)/retina=\(retina)")
                }
            } } }
        }
        print("PASS: \(checks) exact garden pixels across weather, daylight, edge/mirror/offset and Retina geometry")
    }
    static func benchmark(frames: Int) {
        let c = bitmap(), camera = cameras[0].1
        for (weather, mode) in [(WorldWeather.clear, WorldTimeMode.day), (.rain, .night)] {
            let world = SceneWorld(weather: weather, weatherMode: .manual, timeMode: mode)
            for _ in 0..<12 { autoreleasepool {
                OutdoorWorkplaceScene.drawGarden(in: c, bounds: bounds, world: world,
                    at: date, reduceMotion: false, viewport: camera)
            } }
            let start = ProcessInfo.processInfo.systemUptime, cpu = clock()
            for frame in 0..<frames { autoreleasepool {
                OutdoorWorkplaceScene.drawGarden(in: c, bounds: bounds, world: world,
                    at: date.addingTimeInterval(Double(frame) / 30), reduceMotion: false, viewport: camera)
            } }
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            print(String(format: "BENCH %@/%@ frames=%d cpuMsPerFrame=%.4f wallMsPerFrame=%.4f mallocInUseMiB=%.2f mallocReservedMiB=%.2f",
                weather.rawValue, mode.rawValue, frames,
                Double(clock() - cpu) * 1000 / Double(CLOCKS_PER_SEC) / Double(frames),
                (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(frames),
                Double(stats.size_in_use) / 1_048_576, Double(stats.size_allocated) / 1_048_576))
        }
    }
    static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--hashes"), args.indices.contains(index + 1) {
            let result = hashes()
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: URL(fileURLWithPath: args[index + 1]))
            print("HASHES: \(result.count) garden/backdrop frames across weather, daylight, mirrored/wide/offset cameras")
        } else if args.contains("--benchmark") {
            benchmark(frames: 300)
        } else {
            gardenEquivalence()
        }
    }
}

private enum LegacyGardenReference {
    static func draw(in c: CGContext, bounds: CGRect, world: SceneWorld,
                           at date: Date, reduceMotion: Bool, viewport: WorldViewport) {
        guard bounds.width > 0, bounds.height > 0, let image = gardenArtwork else { return }
        let reference = SceneSeamBlend.referenceSize
        let placements: [(CGRect, CGPoint, CGFloat, Bool)]
        if viewport.seams.isEmpty {
            let scale = viewport.display.height / reference.height
            placements = [(viewport.display,
                CGPoint(x: viewport.display.maxX - reference.width * scale, y: viewport.display.minY), scale, false)]
        } else {
            placements = viewport.seams.compactMap { seam in
                let exterior = CGRect(x: seam.roomOnRight ? viewport.canvas.minX : seam.boundaryX,
                    y: viewport.canvas.minY,
                    width: seam.roomOnRight ? seam.boundaryX - viewport.canvas.minX : viewport.canvas.maxX - seam.boundaryX,
                    height: viewport.canvas.height)
                guard exterior.width > 0, exterior.intersects(viewport.display) else { return nil }
                let scale = (seam.upperY - seam.lowerY) / reference.height
                return (exterior, CGPoint(x: seam.boundaryX + (seam.roomOnRight ? -1 : 1) * reference.width * scale,
                    y: seam.lowerY), scale, !seam.roomOnRight)
            }
        }
        let environment = world.environment(at: date)
        let time = WorldAtmosphere.motionTime(at: date, reduceMotion: reduceMotion)
        c.saveGState(); c.clip(to: bounds)
        c.concatenate(viewport.mapping(into: bounds))
        c.interpolationQuality = .none
        c.setShouldAntialias(false)
        for (exterior, origin, scale, mirrored) in placements {
            c.saveGState(); c.clip(to: exterior)
            c.translateBy(x: origin.x, y: origin.y)
            c.scaleBy(x: mirrored ? -scale : scale, y: scale)
            let nativeRect = CGRect(origin: .zero, size: reference)
            let outside = CGRect(x: mirrored ? (origin.x - exterior.maxX) / scale : (exterior.minX - origin.x) / scale,
                y: (exterior.minY - origin.y) / scale, width: exterior.width / scale, height: exterior.height / scale)
            // On unusually wide displays extend only the open garden edge.
            // This keeps the path level and the pixels square; stretching the
            // entire foreground would change the room/yard scale again.
            if let edge = gardenEdge {
                let tileWidth: CGFloat = 64
                for index in Int(floor(outside.minX / tileWidth))..<Int(ceil(outside.maxX / tileWidth)) {
                    let tile = CGRect(x: CGFloat(index) * tileWidth, y: 0,
                                      width: tileWidth, height: reference.height)
                    if nativeRect.contains(tile) { continue }
                    c.saveGState()
                    let uncovered = CGMutablePath(); uncovered.addRect(outside); uncovered.addRect(nativeRect)
                    c.addPath(uncovered); c.clip(using: .evenOdd)
                    c.draw(edge, in: tile)
                    c.clip(to: tile, mask: edge)
                    WorldAtmosphere.grade(in: c, rect: tile, environment: environment, weather: world.weather, interior: false)
                    // Keep the exact native garden particle coordinates while
                    // clipping to this extension tile. The even-odd clip above
                    // excludes the main sprite, so no particle is drawn twice.
                    WorldAtmosphere.precipitation(in: c, rect: outside, weather: world.weather,
                        time: time, reduceMotion: reduceMotion)
                    c.restoreGState()
                }
            }
            c.draw(image, in: nativeRect)
            c.saveGState(); c.clip(to: nativeRect, mask: image)
            WorldAtmosphere.grade(in: c, rect: nativeRect, environment: environment, weather: world.weather, interior: false)
            c.restoreGState()
            // Precipitation on the distant landscape is already behind these
            // sprites. Repaint it only on opaque garden pixels, using one clock.
            c.saveGState(); c.clip(to: nativeRect, mask: image)
            WorldAtmosphere.precipitation(in: c, rect: outside, weather: world.weather,
                time: time, reduceMotion: reduceMotion)
            c.restoreGState()
            c.restoreGState()
        }
        c.restoreGState()
    }

    private static let gardenArtwork = RoomAssets.gardenForeground.flatMap(PixelAssetTransparency.cleaned)
    private static let gardenEdge: CGImage? = {
        guard let image = gardenArtwork else { return nil }
        let width = max(1, (CGFloat(image.width) * 64 / SceneSeamBlend.referenceSize.width).rounded())
        return image.cropping(to: CGRect(x: CGFloat(image.width) - width, y: 0,
                                        width: width, height: CGFloat(image.height)))
    }()

}
