import AppKit
import CryptoKit
import Darwin

/// Synthetic, bounded checks; no app windows, observers or personal state.
@main enum BackdropMaskPerformanceTests {
    static let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    static let date = Date(timeIntervalSince1970: 1_793_661_610)

    static func bitmap(scale: Int) -> CGContext {
        let context = CGContext(data: nil, width: 1920 * scale, height: 1080 * scale,
            bitsPerComponent: 8, bytesPerRow: 1920 * scale * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        return context
    }

    static var cameras: [(String, WorldViewport)] {
        let room = CGRect(x: 0, y: 0, width: 1672, height: 941)
        let wide = CGRect(x: -2600, y: 0, width: 2600, height: 941)
        let mirrored = CGRect(x: 1672, y: 0, width: 2600, height: 941)
        let raised = CGRect(x: -1672, y: 120, width: 1672, height: 941)
        return [("normal", .companion(for: .outdoors)), ("room", .companion(for: .room)),
            ("wide", WorldViewport(canvas: wide.union(room), display: wide,
                seams: [WorldSeam(boundaryX: 0, lowerY: 0, upperY: 941, roomOnRight: true)])!),
            ("mirrored", WorldViewport(canvas: room.union(mirrored), display: mirrored,
                seams: [WorldSeam(boundaryX: 1672, lowerY: 0, upperY: 941, roomOnRight: false)])!),
            ("raised", WorldViewport(canvas: room.union(raised), display: raised,
                seams: [WorldSeam(boundaryX: 0, lowerY: 120, upperY: 941, roomOnRight: true)])!)]
    }

    static func draw(in context: CGContext, world: SceneWorld, camera: WorldViewport,
                     throughGlass: Bool, at date: Date, legacy: Bool) {
        context.saveGState()
        let target: CGRect
        if throughGlass {
            context.scaleBy(x: 1920 / 1672, y: 1080 / 941)
            WindowGlassMask.clip(in: context)
            target = CGRect(x: 0, y: 0, width: 1672, height: 941)
        } else { target = bounds }
        if legacy {
            LegacyBackdropReference.drawBackdrop(in: context, bounds: target, world: world,
                at: date, reduceMotion: false, viewport: camera)
        } else {
            OutdoorWorkplaceScene.drawBackdrop(in: context, bounds: target, world: world,
                at: date, reduceMotion: false, viewport: camera)
        }
        context.restoreGState()
    }

    static func hash(_ context: CGContext) -> SHA256.Digest {
        SHA256.hash(data: Data(bytesNoCopy: context.data!, count: context.bytesPerRow * context.height,
                              deallocator: .none))
    }

    static func equivalence() {
        var checks = 0
        for scale in [1, 2] {
            let optimized = bitmap(scale: scale), original = bitmap(scale: scale)
            for weather in WorldWeather.allCases {
                for mode in [WorldTimeMode.day, .sunset, .night] {
                    let world = SceneWorld(weather: weather, weatherMode: .manual, timeMode: mode)
                    for (name, camera) in cameras {
                        for throughGlass in [false, true] { autoreleasepool {
                            optimized.clear(bounds); original.clear(bounds)
                            draw(in: optimized, world: world, camera: camera,
                                throughGlass: throughGlass, at: date, legacy: false)
                            draw(in: original, world: world, camera: camera,
                                throughGlass: throughGlass, at: date, legacy: true)
                            checks += 1
                            guard hash(optimized) == hash(original) else {
                                fputs("FAIL: \(scale)x \(weather.rawValue)/\(mode.rawValue)/\(name)/glass=\(throughGlass)\n", stderr)
                                exit(1)
                            }
                        } }
                    }
                }
            }
        }
        print("PASS: \(checks) byte-exact backdrop frames across weather, daylight, mirrored/wide/offset cameras, room glass and Retina")
    }

    static func benchmark(frames: Int) {
        let context = bitmap(scale: 1)
        for legacy in [true, false] {
            for throughGlass in [false, true] {
                let camera = WorldViewport.companion(for: throughGlass ? .room : .outdoors)
                for (weather, mode) in [(WorldWeather.clear, WorldTimeMode.day), (.rain, .night)] {
                    let world = SceneWorld(weather: weather, weatherMode: .manual, timeMode: mode)
                    for _ in 0..<8 { autoreleasepool {
                        draw(in: context, world: world, camera: camera,
                            throughGlass: throughGlass, at: date, legacy: legacy)
                    } }
                    let started = ProcessInfo.processInfo.systemUptime, cpu = clock()
                    for index in 0..<frames { autoreleasepool {
                        draw(in: context, world: world, camera: camera, throughGlass: throughGlass,
                            at: date.addingTimeInterval(Double(index) / 30), legacy: legacy)
                    } }
                    var stats = malloc_statistics_t()
                    malloc_zone_statistics(nil, &stats)
                    print(String(format: "BENCH legacy=%@ glass=%@ %@/%@ frames=%d cpuMsPerFrame=%.4f wallMsPerFrame=%.4f mallocInUseMiB=%.2f",
                        String(legacy), String(throughGlass), weather.rawValue, mode.rawValue, frames,
                        Double(clock() - cpu) * 1000 / Double(CLOCKS_PER_SEC) / Double(frames),
                        (ProcessInfo.processInfo.systemUptime - started) * 1000 / Double(frames),
                        Double(stats.size_in_use) / 1_048_576))
                }
            }
        }
    }

    static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        guard RoomAssets.panorama != nil, WindowGlassMask.usesArtworkMask else {
            fputs("FAIL: real panorama and room glass assets required for this comparison\n", stderr)
            exit(1)
        }
        if CommandLine.arguments.contains("--benchmark") { benchmark(frames: 180) }
        else { equivalence() }
    }
}

/// Former full-canvas RGBA-mask path, retained only for pixel/performance comparison.
private enum LegacyBackdropReference {
    private static var artwork: CGImage? { RoomAssets.panorama ?? RoomAssets.outdoors }
    private static var artworkSize: CGSize {
        artwork.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 3344, height: 941)
    }
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "HH:mm"; return f
    }()
    private static let skyMask = mask { r, g, b, row, height in
        row < Int(Double(height) * 0.25) && b > 180 && g > 125 && b > g && g > r
    }
    private static let riverMask = mask { r, g, b, row, height in
        row > Int(Double(height) * 0.30) && row < Int(Double(height) * 0.94)
            && b > Int(Double(r) * 1.08) && g > Int(Double(r) * 1.14) && g > 105 && b > 110
    }

    static func drawBackdrop(in c: CGContext, bounds: CGRect, world: SceneWorld,
                             at date: Date, reduceMotion: Bool, viewport: WorldViewport) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let imageSize = artworkSize
        let scale = max(viewport.canvas.width / imageSize.width, viewport.canvas.height / imageSize.height)
        let imageRect = CGRect(x: viewport.canvas.midX - imageSize.width * scale / 2,
                               y: viewport.canvas.midY - imageSize.height * scale / 2,
                               width: imageSize.width * scale, height: imageSize.height * scale)
        c.saveGState(); c.clip(to: bounds)
        c.concatenate(viewport.mapping(into: bounds))
        c.translateBy(x: imageRect.minX, y: imageRect.minY)
        c.scaleBy(x: scale, y: scale)
        c.interpolationQuality = .none
        let canvas = CGRect(origin: .zero, size: imageSize)
        if let art = artwork { c.draw(art, in: canvas) }
        else {
            c.setFillColor(WorldAtmosphere.color(0x6BA6B8).cgColor); c.fill(canvas)
            c.setFillColor(WorldAtmosphere.color(0x527A53).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height * 0.62))
        }
        let environment = world.environment(at: date)
        let time = WorldAtmosphere.motionTime(at: date, reduceMotion: reduceMotion)
        WorldAtmosphere.grade(in: c, rect: canvas, environment: environment, weather: world.weather, interior: false)
        c.saveGState()
        if let skyMask { c.clip(to: canvas, mask: skyMask) }
        let sky = CGRect(x: 0, y: canvas.height * 0.78, width: canvas.width, height: canvas.height * 0.22)
        WorldAtmosphere.celestial(in: c, sky: sky, environment: environment, weather: world.weather, time: time)
        WorldAtmosphere.clouds(in: c, rect: sky, weather: world.weather, environment: environment, time: time)
        if world.weather == .clear && environment.daylight > 0.3 {
            birds(in: c, canvas: canvas, time: time, daylight: environment.daylight)
        }
        c.restoreGState()
        // Lightning belongs to the shared distant world only. Garden sprites,
        // reminder visitors and all room/task layers are composited afterwards;
        // the room's caller additionally clips this pass to its window glass.
        WorldAtmosphere.lightning(in: c, canvas: canvas, weather: world.weather,
                                  at: date, reduceMotion: reduceMotion)
        water(in: c, canvas: canvas, environment: environment, time: time, weather: world.weather)
        if environment.darkness > 0.25 && world.weather == .clear {
            fireflies(in: c, canvas: canvas, time: time, darkness: environment.darkness)
        }
        WorldAtmosphere.precipitation(in: c, rect: canvas, weather: world.weather, time: time,
                                     reduceMotion: reduceMotion)
        c.restoreGState()
    }

    private static func birds(in c: CGContext, canvas: CGRect, time: Double, daylight: Double) {
        c.saveGState(); c.setShouldAntialias(false)
        c.setFillColor(WorldAtmosphere.color(0x35566A, alpha: CGFloat(daylight) * 0.65).cgColor)
        let group = WorldAtmosphere.positiveRemainder(time / 7, canvas.width + 300) - 150
        let wing = Int(floor(time * 1.8)) % 2 == 0 ? 2.0 : -2.0
        for i in 0..<4 {
            let x = floor((group - Double(i) * 26) / 2) * 2
            let y = canvas.height * 0.85 + Double(i % 2) * 11
            c.fill(CGRect(x: x, y: y, width: 4, height: 2))
            c.fill(CGRect(x: x - 4, y: y + wing, width: 4, height: 2))
            c.fill(CGRect(x: x + 4, y: y + wing, width: 4, height: 2))
        }
        c.restoreGState()
    }

    private static func water(in c: CGContext, canvas: CGRect, environment: WorldEnvironment,
                              time: Double, weather: WorldWeather) {
        guard let riverMask else { return }
        c.saveGState(); c.clip(to: canvas, mask: riverMask); c.setShouldAntialias(false)
        let alpha = CGFloat(0.14 + environment.daylight * 0.19)
            * (weather == .thunderstorm ? 0.30 : weather == .rain ? 0.45 : 1)
        for i in 0..<168 {
            let x = WorldAtmosphere.random(i * 3 + 201) * canvas.width
            let y = canvas.height * (0.10 + WorldAtmosphere.random(i * 3 + 202) * 0.59)
            let pulse = 0.5 + 0.5 * sin(time / 3.8 + Double(i) * 4.7)
            c.setFillColor(WorldAtmosphere.color(environment.darkness > 0.5 ? 0xB6D1E6 : 0xDAF0D6,
                                                 alpha: alpha * CGFloat(pulse)).cgColor)
            c.fill(CGRect(x: floor(x / 3) * 3, y: floor(y / 3) * 3,
                          width: 3 * Double(2 + i % 5), height: 2).integral)
        }
        c.restoreGState()
    }

    private static func fireflies(in c: CGContext, canvas: CGRect, time: Double, darkness: Double) {
        c.saveGState(); c.setShouldAntialias(false)
        for i in 0..<24 {
            let x = canvas.width * (0.08 + WorldAtmosphere.random(i * 4 + 44) * 0.75) + sin(time / 11 + Double(i)) * 7
            let y = canvas.height * (0.12 + WorldAtmosphere.random(i * 4 + 45) * 0.32) + sin(time / 8 + Double(i) * 2) * 5
            let pulse = max(0, sin(time / 3 + Double(i) * 1.7))
            c.setFillColor(WorldAtmosphere.color(0xD4D883, alpha: CGFloat(pulse * darkness * 0.8)).cgColor)
            c.fill(CGRect(x: floor(x / 2) * 2, y: floor(y / 2) * 2, width: 2, height: 2))
        }
        c.restoreGState()
    }

    /// Masks are computed once from the shared panorama, before any night tint.
    /// Moving clouds and reflections then stay behind the painted silhouettes.
    private static func mask(_ predicate: (Int, Int, Int, Int, Int) -> Bool) -> CGImage? {
        guard let image = artwork else { return nil }
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for row in 0..<h {
            for x in 0..<w {
                let i = (row * w + x) * 4
                let alpha: UInt8 = predicate(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), row, h) ? 255 : 0
                pixels[i] = alpha; pixels[i + 1] = alpha; pixels[i + 2] = alpha; pixels[i + 3] = alpha
            }
        }
        return context.makeImage()
    }
}
