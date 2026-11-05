import AppKit

/// Atmospheric motion is derived from wall-clock time, shared by every window
/// and the independent saver process. No renderer owns another timer or clock.
enum WorldAtmosphere {
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static func motionTime(at date: Date, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    }

    struct LightningSample: Equatable {
        let eventIndex: Int
        let elapsed: TimeInterval
        let intensity: CGFloat
        let xFraction: CGFloat
        let bendsRight: Bool
    }
    static let lightningDuration: TimeInterval = 0.8
    static let maximumLightningOpacity: CGFloat = 0.58
    static let maximumLightningGlowOpacity: CGFloat = 0.07

    /// One softly fading event per 35-second bucket, jittered by ten seconds.
    /// Adjacent event starts are therefore always 25–45 seconds apart. Index
    /// and time use the reference-date epoch, never a host's animation uptime.
    static func lightningEventTime(index: Int) -> TimeInterval {
        Double(index) * 35 + 5 + random(index &* 61 &+ 901) * 10
    }

    static func lightningSample(at date: Date, weather: WorldWeather,
                                reduceMotion: Bool) -> LightningSample? {
        guard weather == .thunderstorm, !reduceMotion else { return nil }
        let clock = date.timeIntervalSinceReferenceDate
        guard clock.isFinite, abs(clock) < Double(Int.max / 128) else { return nil }
        let index = Int(floor(clock / 35))
        let elapsed = clock - lightningEventTime(index: index)
        guard elapsed >= 0, elapsed < lightningDuration else { return nil }
        let rise = 0.12
        let value: Double
        if elapsed < rise { value = elapsed / rise }
        else {
            let tail = 1 - (elapsed - rise) / (lightningDuration - rise)
            value = tail * tail * (3 - 2 * tail)
        }
        return LightningSample(eventIndex: index, elapsed: elapsed,
            intensity: CGFloat(max(0, min(1, value))),
            xFraction: 0.18 + CGFloat(random(index &* 43 &+ 677)) * 0.66,
            bendsRight: random(index &* 29 &+ 451) > 0.5)
    }

    /// The lower foreground is deliberately outside this region. The room's
    /// caller clips the same distant-world pass again through the actual glass.
    static func lightningRegion(in canvas: CGRect) -> CGRect {
        CGRect(x: canvas.minX, y: canvas.minY + canvas.height * 0.56,
               width: canvas.width, height: canvas.height * 0.41)
    }

    static func lightning(in c: CGContext, canvas: CGRect, weather: WorldWeather,
                          at date: Date, reduceMotion: Bool) {
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0,
              let sample = lightningSample(at: date, weather: weather, reduceMotion: reduceMotion),
              sample.intensity > 0 else { return }
        let region = lightningRegion(in: canvas)
        let pixel = max(2, floor(canvas.height / 280))
        let originX = canvas.minX + sample.xFraction * canvas.width
        let sign: CGFloat = sample.bendsRight ? 1 : -1
        func point(_ dx: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: floor((originX + dx * canvas.width * sign) / pixel) * pixel,
                    y: floor((canvas.minY + y * canvas.height) / pixel) * pixel)
        }
        let vertices = [point(0, 0.94), point(-0.008, 0.88), point(0.005, 0.82),
                        point(-0.010, 0.76), point(-0.002, 0.70), point(-0.016, 0.61)]
        let bolt = CGMutablePath()
        func addSegment(_ a: CGPoint, _ b: CGPoint) {
            let steps = max(1, Int(ceil(max(abs(b.x - a.x), abs(b.y - a.y)) / pixel)))
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                bolt.addRect(CGRect(x: floor((a.x + (b.x - a.x) * t) / pixel) * pixel,
                    y: floor((a.y + (b.y - a.y) * t) / pixel) * pixel,
                    width: pixel * 2, height: pixel * 2))
            }
        }
        for index in 1..<vertices.count { addSegment(vertices[index - 1], vertices[index]) }
        addSegment(vertices[2], point(0.024, 0.77))
        addSegment(point(0.024, 0.77), point(0.018, 0.73))
        c.saveGState(); c.clip(to: region); c.setShouldAntialias(false)
        // A small stepped cloud glow, never a full-screen brightness flash.
        let glow = CGRect(x: originX - canvas.width * 0.035, y: canvas.minY + canvas.height * 0.65,
                          width: canvas.width * 0.07, height: canvas.height * 0.28).integral
        let glowShape = CGMutablePath()
        glowShape.addRect(glow.insetBy(dx: pixel * 4, dy: 0))
        glowShape.addRect(CGRect(x: glow.minX, y: glow.minY + pixel * 4,
            width: glow.width, height: max(0, glow.height - pixel * 8)))
        c.setFillColor(color(0xA5BCD0, alpha: sample.intensity * maximumLightningGlowOpacity).cgColor)
        c.addPath(glowShape); c.fillPath()
        // Fill the union once: intersecting pixel segments cannot accumulate
        // alpha into an unexpectedly bright flash at the lightning's corners.
        c.addPath(bolt)
        c.setFillColor(color(0xB8D1DF, alpha: sample.intensity * maximumLightningOpacity).cgColor)
        c.fillPath()
        c.restoreGState()
    }

    static func grade(in c: CGContext, rect: CGRect, environment: WorldEnvironment,
                      weather: WorldWeather, interior: Bool) {
        c.saveGState()
        // The room keeps warm indoor light while the landscape becomes a cool
        // moonlit valley. Native monitor information is drawn after this pass.
        let night = CGFloat(environment.darkness)
        if night > 0.001 {
            c.setBlendMode(.multiply)
            c.setFillColor(color(interior ? 0x6B789D : 0x34446B, alpha: night * (interior ? 0.64 : 0.88)).cgColor)
            c.fill(rect)
        }
        if environment.sunset > 0.001 {
            c.setBlendMode(.softLight)
            c.setFillColor(color(0xDB8055, alpha: CGFloat(environment.sunset) * (interior ? 0.23 : 0.40)).cgColor)
            c.fill(rect)
        }
        if weather != .clear {
            c.setBlendMode(.sourceAtop)
            let amount: CGFloat
            switch weather {
            case .clear: amount = 0
            case .cloudy: amount = 0.12
            case .rain: amount = 0.23
            case .snow: amount = 0.14
            case .thunderstorm: amount = 0.38
            }
            c.setFillColor(color(weather == .snow ? 0xC0D3DD : weather == .thunderstorm ? 0x40566D : 0x657C89,
                                 alpha: amount * (interior ? 0.5 : 1)).cgColor)
            c.fill(rect)
        }
        c.restoreGState()
    }

    /// Long, quiet cloud banks use hard pixel steps rather than soft vector ovals.
    static func clouds(in c: CGContext, rect: CGRect, weather: WorldWeather,
                       environment: WorldEnvironment, time: Double, compact: Bool = false) {
        c.saveGState(); c.clip(to: rect); c.setShouldAntialias(false)
        let storm = weather == .thunderstorm
        let weatherClouds = weather != .clear
        let count = storm ? 10 : weatherClouds ? 6 : 3
        let pixel = max(1.5, rect.height / (compact ? 45 : 70))
        let darkness = CGFloat(environment.darkness)
        let alpha: CGFloat = storm ? 0.52 + darkness * 0.08 : weatherClouds ? 0.27 + darkness * 0.08 : 0.18
        for i in 0..<count {
            let width = rect.width * (storm ? 0.31 : weatherClouds ? 0.23 : 0.16) * (0.8 + random(i + 71) * 0.55)
            let period = rect.width + width * 2
            let speed = rect.width / (storm ? 1500 : weatherClouds ? 2100 : 3600)
            let phase = (time * speed + random(i + 17) * period).truncatingRemainder(dividingBy: period)
            let x = floor((rect.minX + CGFloat(phase) - width) / pixel) * pixel
            let y = floor((rect.minY + rect.height * (0.24 + CGFloat(random(i + 37)) * 0.56)) / pixel) * pixel
            let ux = width / 18
            let uy = max(pixel, rect.height * (storm ? 0.045 : 0.027))
            // A stepped, asymmetric silhouette, with two rounded tufts and a
            // narrow shaded underside, reads as a cloud rather than a long bar.
            let contour: [CGPoint] = [CGPoint(x:0,y:1),CGPoint(x:1,y:1),CGPoint(x:1,y:2),
                CGPoint(x:3,y:2),CGPoint(x:3,y:4),CGPoint(x:4,y:4),CGPoint(x:4,y:5),
                CGPoint(x:7,y:5),CGPoint(x:7,y:4),CGPoint(x:9,y:4),CGPoint(x:9,y:6),
                CGPoint(x:12,y:6),CGPoint(x:12,y:5),CGPoint(x:14,y:5),CGPoint(x:14,y:3),
                CGPoint(x:16,y:3),CGPoint(x:16,y:2),CGPoint(x:18,y:2),CGPoint(x:18,y:0),
                CGPoint(x:0,y:0)]
            let shape = CGMutablePath()
            shape.addLines(between: contour.map { CGPoint(x: x + floor($0.x * ux / pixel) * pixel,
                                                         y: y + floor($0.y * uy / pixel) * pixel) })
            shape.closeSubpath()
            c.saveGState(); c.addPath(shape); c.clip()
            c.setFillColor(color(storm ? 0x3E5065 : weather == .rain ? 0x687C90 : 0xD3E2E2, alpha: alpha).cgColor)
            c.fill(CGRect(x:x,y:y,width:width,height:uy * 6))
            c.setFillColor(color(storm ? 0x26384D : weather == .rain ? 0x344C65 : 0x8FAABF,
                                 alpha: alpha * (storm ? 0.55 : 0.38)).cgColor)
            c.fill(CGRect(x:x,y:y,width:width,height:uy * 1.2))
            c.restoreGState()
        }
        c.restoreGState()
    }

    static func celestial(in c: CGContext, sky: CGRect, environment: WorldEnvironment,
                          weather: WorldWeather, time: Double) {
        guard sky.width > 0, sky.height > 0 else { return }
        c.saveGState(); c.clip(to: sky); c.setShouldAntialias(false)
        let night = CGFloat(environment.darkness)
        if night > 0.12 && weather == .clear {
            let pixel = max(1.5, sky.height / 70)
            let starCount = Int(max(12, min(62, sky.width / 16)))
            for i in 0..<starCount {
                let x = sky.minX + CGFloat(random(i * 3 + 9)) * sky.width
                let y = sky.minY + CGFloat(random(i * 3 + 10)) * sky.height
                let pulse = 0.7 + sin(time / 7 + Double(i) * 2.6) * 0.15
                c.setFillColor(color(i % 4 == 0 ? 0xE6CFA6 : 0xCAD7E8, alpha: night * CGFloat(pulse)).cgColor)
                c.fill(CGRect(x: floor(x / pixel) * pixel, y: floor(y / pixel) * pixel,
                              width: pixel * (i % 9 == 0 ? 2 : 1), height: pixel).integral)
                if i % 9 == 0 {
                    c.fill(CGRect(x: floor(x / pixel) * pixel, y: floor(y / pixel) * pixel - pixel,
                                  width: pixel, height: pixel * 3).integral)
                }
            }
            let moon = CGRect(x: sky.minX + sky.width * 0.37, y: sky.minY + sky.height * 0.56,
                              width: max(14, sky.height * 0.16), height: max(14, sky.height * 0.16))
            c.setFillColor(color(0xE9DFBD, alpha: night * 0.94).cgColor)
            c.fill(moon.insetBy(dx: 0, dy: moon.height * 0.18).integral)
            c.fill(moon.insetBy(dx: moon.width * 0.18, dy: 0).integral)
            c.setFillColor(color(0x8295B3, alpha: night * 0.8).cgColor)
            c.fill(CGRect(x: moon.minX, y: moon.midY, width: moon.width * 0.45, height: moon.height * 0.5).integral)
        }
        c.restoreGState()
    }

    static func precipitation(in c: CGContext, rect: CGRect, weather: WorldWeather,
                              time: Double, reduceMotion: Bool, compact: Bool = false) {
        guard weather == .rain || weather == .snow || weather == .thunderstorm else { return }
        c.saveGState(); c.clip(to: rect); c.setShouldAntialias(false)
        let snowy = weather == .snow
        let storm = weather == .thunderstorm
        let count = compact ? (snowy ? 36 : storm ? 80 : 48) : (snowy ? 180 : storm ? 360 : 220)
        let pixel = max(1.5, min(rect.width / 520, rect.height / 250))
        let period = rect.height + 80
        for i in 0..<count {
            let depth = 0.45 + random(i + 91) * 0.55
            let speed = snowy ? 15 + 25 * depth : storm ? 270 + 230 * depth : 210 + 170 * depth
            let drift = snowy ? sin(time * 0.35 + Double(i)) * 15 : time * (storm ? -28 : -16) * depth
            let x = rect.minX + CGFloat(positiveRemainder(random(i * 2 + 301) * Double(rect.width) + drift,
                                                        Double(rect.width)))
            let phase = positiveRemainder(random(i * 2 + 302) * Double(period) + time * speed, Double(period))
            let y = rect.maxY + 40 - CGFloat(phase)
            let alpha = CGFloat((snowy ? 0.62 : storm ? 0.34 : 0.28) * depth)
            c.setFillColor(color(snowy ? 0xE0EAF0 : 0xBAD0E1, alpha: alpha).cgColor)
            let length = snowy ? pixel * (i % 5 == 0 ? 2 : 1) : pixel * CGFloat(storm ? 7 + depth * 6 : 5 + depth * 5)
            let fx = (x / pixel).rounded() * pixel
            let fy = (y / pixel).rounded() * pixel
            c.fill(CGRect(x: fx, y: fy, width: pixel, height: length).integral)
            if snowy && i % 5 == 0 { c.fill(CGRect(x: fx - pixel, y: fy + pixel, width: pixel * 3, height: pixel).integral) }
            if !snowy && !reduceMotion {
                c.fill(CGRect(x: fx + pixel, y: fy - pixel * 2, width: pixel, height: length * 0.65).integral)
            }
        }
        c.restoreGState()
    }

    static func drawRoom(in c: CGContext, world: SceneWorld, at date: Date, reduceMotion: Bool,
                         nightArtworkBlend: Double = 0,
                         visibleRect: CGRect = CGRect(x: 0, y: 0, width: 1672, height: 941),
                         viewport: WorldViewport = .companion(for: .room)) {
        let environment = world.environment(at: date)
        let room = CGRect(x: 0, y: 0, width: 1672, height: 941)
        var gradeEnvironment = environment
        gradeEnvironment.darkness *= 1 - min(1, max(0, nightArtworkBlend))
        grade(in: c, rect: room, environment: gradeEnvironment, weather: world.weather, interior: true)
        c.saveGState()
        WindowGlassMask.clip(in: c)
        // Glass is an opening onto the exact same global panorama seen by the
        // adjacent outdoor monitor, with no independent crop or weather pass.
        OutdoorWorkplaceScene.drawBackdrop(in: c, bounds: visibleRect, world: world,
            at: date, reduceMotion: reduceMotion, viewport: viewport)
        c.restoreGState()
        if environment.darkness > 0.03 {
            let lamps = RoomAssets.usesFlatForeground
                ? [CGPoint(x: 1205, y: 780), CGPoint(x: 1400, y: 560)]
                : [CGPoint(x: 1168, y: 783), CGPoint(x: 1365, y: 536), CGPoint(x: 116, y: 170)]
            for lamp in lamps {
                lampGlow(in: c, center: lamp, radius: lamp.x > 1000 ? 95 : 75,
                         alpha: CGFloat(environment.darkness) * 0.24)
            }
        }
    }

    // Kept as a shared geometric safety boundary for renderer diagnostics.
    static var windowBounds: CGRect { WindowGlassMask.bounds }
    static var windowGlassPath: CGPath { WindowGlassMask.path }

    private static func lampGlow(in c: CGContext, center: CGPoint, radius: CGFloat, alpha: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0xF8B34C, alpha: alpha).cgColor, color(0xF8B34C, alpha: 0).cgColor] as CFArray,
            locations: [0, 1]) else { return }
        c.saveGState(); c.setBlendMode(.screen)
        c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                             endRadius: radius, options: [])
        c.restoreGState()
    }

    static func random(_ value: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: value) &+ 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return Double((x ^ (x >> 31)) & 0x00FF_FFFF) / Double(0x0100_0000)
    }
    static func positiveRemainder(_ value: Double, _ modulus: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: modulus)
        return result < 0 ? result + modulus : result
    }
}
