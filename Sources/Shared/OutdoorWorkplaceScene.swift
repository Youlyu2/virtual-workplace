import AppKit

/// Every screen crops one panoramic world. The room's glass uses this exact
/// backdrop pass, so landscape scale, horizon and weather continue across it.
enum OutdoorWorkplaceScene {
    static var isAvailable: Bool { RoomAssets.panorama != nil || RoomAssets.outdoors != nil }
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

    static func draw(in c: CGContext, bounds: CGRect, world: SceneWorld,
                     at date: Date, reduceMotion: Bool, viewport: WorldViewport) {
        drawBackdrop(in: c, bounds: bounds, world: world, at: date,
                     reduceMotion: reduceMotion, viewport: viewport)
        drawGarden(in: c, bounds: bounds, world: world, at: date,
                   reduceMotion: reduceMotion, viewport: viewport)
        SceneSeamBlend.draw(in: c, bounds: bounds, world: world, at: date, viewport: viewport)
        // A local HUD is not part of the shared landscape and is never drawn
        // into the room's window or repeated at a panorama seam.
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.height / 941, bounds.width / 400)
        c.saveGState(); c.clip(to: bounds)
        c.translateBy(x: bounds.minX, y: bounds.minY); c.scaleBy(x: scale, y: scale)
        plaque(in: c, visible: CGRect(x: 0, y: 0, width: bounds.width / scale, height: bounds.height / scale),
               world: world, environment: world.environment(at: date), at: date)
        c.restoreGState()
    }

    /// The close garden is a separate, flat tile plane. Its grid is sized by
    /// display height, never by the distant panorama's width or crop. In a
    /// mixed pair the shared seam gives both hosts exactly the same path level.
    static func drawGarden(in c: CGContext, bounds: CGRect, world: SceneWorld,
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
        // Clear daylight has neither a tint nor precipitation. Avoid converting
        // a full foreground image into a clipping mask for an empty pass.
        let hasEffects = world.weather != .clear
            || environment.darkness > 0.001 || environment.sunset > 0.001
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
                    if hasEffects {
                        c.clip(to: tile, mask: edge)
                        WorldAtmosphere.grade(in: c, rect: tile, environment: environment, weather: world.weather, interior: false)
                        // Keep native particle coordinates on extension tiles.
                        // The even-odd clip excludes the main foreground.
                        WorldAtmosphere.precipitation(in: c, rect: outside, weather: world.weather,
                            time: time, reduceMotion: reduceMotion)
                    }
                    c.restoreGState()
                }
            }
            c.draw(image, in: nativeRect)
            if hasEffects {
                // Tint and foreground rain share one unchanged RGBA alpha
                // clip, avoiding a second image-mask conversion per frame.
                c.saveGState(); c.clip(to: nativeRect, mask: image)
                WorldAtmosphere.grade(in: c, rect: nativeRect, environment: environment, weather: world.weather, interior: false)
                WorldAtmosphere.precipitation(in: c, rect: outside, weather: world.weather,
                    time: time, reduceMotion: reduceMotion)
                c.restoreGState()
            }
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

    /// Render the same world camera without local overlays. `bounds` can be the
    /// complete outdoor view or the room's visible stage rectangle under a mask.
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

    private static func plaque(in c: CGContext, visible: CGRect, world: SceneWorld,
                               environment: WorldEnvironment, at date: Date) {
        let r = CGRect(x: visible.minX + 24, y: visible.minY + 22, width: min(288, visible.width - 48), height: 38)
        c.saveGState(); c.setShouldAntialias(false)
        c.setFillColor(WorldAtmosphere.color(0x433C2D, alpha: 0.82).cgColor); c.fill(r.integral)
        c.setFillColor(WorldAtmosphere.color(0xD4BF8D, alpha: 0.9).cgColor)
        c.fill(CGRect(x: r.minX + 2, y: r.minY + 2, width: r.width - 4, height: 1))
        c.fill(CGRect(x: r.minX + 2, y: r.maxY - 3, width: r.width - 4, height: 1))
        c.setShouldAntialias(true)
        let text = "\(dateFormat.string(from: date))   \(world.weather.title) · \(environment.title)"
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: CGRect(x: r.minX + 13, y: r.minY + 9, width: r.width - 26, height: 20),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                             .foregroundColor: WorldAtmosphere.color(0xEFE2BD), .paragraphStyle: style])
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
