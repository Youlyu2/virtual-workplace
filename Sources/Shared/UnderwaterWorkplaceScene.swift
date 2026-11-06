import AppKit

/// The two ocean plates share a simulation clock so movement agrees across hosts.
enum UnderwaterWorkplaceScene {
    private static let canvasSize = CGSize(width: 1672, height: 941)
    static func draw(in c: CGContext, bounds: CGRect, deep: Bool, world: SceneWorld,
                     at date: Date, reduceMotion: Bool, animationOffset: TimeInterval = 0) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(bounds.width / canvasSize.width, bounds.height / canvasSize.height)
        c.saveGState()
        c.clip(to: bounds)
        c.translateBy(x: bounds.midX - canvasSize.width * scale / 2,
                      y: bounds.midY - canvasSize.height * scale / 2)
        c.scaleBy(x: scale, y: scale)
        c.interpolationQuality = .none
        c.setShouldAntialias(false)
        let canvas = CGRect(origin: .zero, size: canvasSize)
        if let plate = deep ? RoomAssets.deepSea : RoomAssets.shallowSea {
            c.draw(plate, in: canvas)
        } else {
            fill(c, canvas, deep ? 0x103746 : 0x57B8AA)
        }

        let light = world.environment(at: date)
        let (clarity, drift, particles) = waterSettings(world.weather)
        fill(c, canvas, deep ? 0x092233 : 0x12344C, alpha: light.darkness * (deep ? 0.28 : 0.48))
        fill(c, canvas, deep ? 0x4A7776 : 0x567C70, alpha: clarity)
        let seconds = date.timeIntervalSinceReferenceDate
        let clock = (seconds.isFinite ? seconds : 0) + animationOffset
        let phase = reduceMotion ? 28.0 + animationOffset : clock

        // Stepped glints move horizontally in the upper water column.
        for row in 0..<4 {
            for segment in 0..<15 {
                let x = CGFloat(segment * 116 + row * 33)
                let wave = (sin(phase * 0.31 + Double(segment) * 0.77 + Double(row)) * 14).rounded()
                let y = CGFloat(875 - row * 41) + wave
                fill(c, CGRect(x: x, y: y, width: CGFloat(26 + (segment % 5) * 9), height: 3),
                     0xF6FFDB, alpha: (deep ? 0.08 : 0.22) * (0.34 + 0.66 * light.daylight))
            }
        }

        if deep {
            OceanWildlife.drawDeep(in: c, phase: phase, clock: clock, reduceMotion: reduceMotion, haze: clarity)
        } else {
            OceanWildlife.drawShallowDolphin(in: c, clock: clock, reduceMotion: reduceMotion, haze: clarity)
            ShallowDiveScene.drawReefFish(in: c, phase: phase)
        }

        for i in 0..<particles {
            let x = WorldAtmosphere.positiveRemainder(Double(i * 107) + phase * drift, 1672)
            let y = WorldAtmosphere.positiveRemainder(Double(i * 71) + phase * (world.weather == .snow ? -8 : 4), 941)
            let side: CGFloat = i % 4 == 0 ? 4 : 2
            fill(c, CGRect(x: x, y: y, width: side, height: side), 0xBDF0DE, alpha: 0.32)
        }
        for i in 0..<19 {
            let y = WorldAtmosphere.positiveRemainder(phase * Double(21 + i % 3 * 7) + Double(i * 91), 960) - 16
            let x = Double(74 + i * 85) + sin(y * 0.015) * 19
            let side = CGFloat(6 + i % 4 * 3)
            if deep {
                fill(c, CGRect(x: x + 2, y: y, width: side - 4, height: 2), 0xD2FFED, alpha: 0.45)
                fill(c, CGRect(x: x + 2, y: y + side - 2, width: side - 4, height: 2), 0xD2FFED, alpha: 0.7)
                fill(c, CGRect(x: x, y: y + 2, width: 2, height: side - 4), 0xD2FFED, alpha: 0.52)
                fill(c, CGRect(x: x + side - 2, y: y + 2, width: 2, height: side - 4), 0xD2FFED, alpha: 0.38)
            } else {
                c.setStrokeColor(WorldAtmosphere.color(0xD2FFED, alpha: 0.65).cgColor)
                c.setLineWidth(1.5)
                c.strokeEllipse(in: CGRect(x: x, y: y, width: side, height: side))
            }
        }
        c.restoreGState()
    }

    private static func waterSettings(_ weather: WorldWeather) -> (CGFloat, Double, Int) {
        switch weather {
        case .clear:        return (0, 9, 12)
        case .cloudy:       return (0.14, 14, 30)
        case .rain:         return (0.20, 32, 44)
        case .snow:         return (0.08, 6, 76)
        case .thunderstorm: return (0.37, 66, 90)
        }
    }

    // A small grayscale plate lets the label follow the same cropped artwork
    // in every host without reading pixels from the live drawing context.
    private static let contrastMapSize = 64
    private static let shallowContrastMap: [UInt8] = {
        let side = contrastMapSize
        guard let artwork = RoomAssets.shallowSea,
              let sample = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                     bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = sample.data else { return [] }
        sample.interpolationQuality = .high
        sample.draw(artwork, in: CGRect(x: 0, y: 0, width: side, height: side))
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side))
    }()

    static func shallowTextIsDark(behind box: CGRect, in viewport: CGSize, world: SceneWorld, at date: Date) -> Bool {
        let cover = max(viewport.width / canvasSize.width, viewport.height / canvasSize.height)
        let width = canvasSize.width * cover
        let height = canvasSize.height * cover
        let left = (viewport.width - width) / 2
        let bottom = (viewport.height - height) / 2
        let side = contrastMapSize
        var sum = 0.0
        for point in [
            CGPoint(x: box.midX, y: box.midY),
            CGPoint(x: box.midX - box.width / 4, y: box.midY),
            CGPoint(x: box.midX + box.width / 4, y: box.midY),
            CGPoint(x: box.midX, y: box.midY - box.height / 5),
            CGPoint(x: box.midX, y: box.midY + box.height / 5)
        ] {
            let column = max(0, min(side - 1, Int((point.x - left) / width * CGFloat(side))))
            let row = max(0, min(side - 1, Int((1 - (point.y - bottom) / height) * CGFloat(side))))
            sum += shallowContrastMap.isEmpty ? 0.63 : Double(shallowContrastMap[row * side + column]) / 255
        }
        let darkening = world.environment(at: date).darkness * 0.48
        let clarity = waterSettings(world.weather).0
        let lit = sum / 5 * (1 - darkening) + 0.18 * darkening
        let luminance = lit * (1 - clarity) + 0.44 * clarity
        return luminance >= 0.56
    }

    static func badge(in c: CGContext, bounds: CGRect, deep: Bool, world: SceneWorld, pendingAlert: Bool = false) {
        let s = min(bounds.width / 710, bounds.height / 470, 1)
        guard s > 0 else { return }
        let w: CGFloat = (deep ? 250 : 220) + (pendingAlert ? 94 : 0)
        let box = CGRect(x: bounds.minX + 20 * s, y: bounds.minY + 18 * s, width: w * s, height: 44 * s)
        fill(c, box, 0x123B45, alpha: 0.90)
        fill(c, CGRect(x: box.minX, y: box.minY, width: 4 * s, height: box.height),
             pendingAlert || world.weather == .thunderstorm ? 0xFFB16F : 0x75D8C2)
        let depth = deep ? "深海  50–130 m" : "浅海  0–50 m"
        let notice = pendingAlert ? "  ·  待办超时" : ""
        ("\(depth)  ·  \(world.theme.title(for: world.weather))\(notice)" as NSString).draw(
            in: box.insetBy(dx: 12 * s, dy: 12 * s),
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14 * s, weight: .medium),
                             .foregroundColor: WorldAtmosphere.color(0xE2FCF3)])
    }

    /// Draw gear on the existing pose anchors, alongside the original animation.
    static func gear(in c: CGContext, feet: CGPoint, height: CGFloat, tank: Bool = true,
                     scale: CGFloat = 1, visor: Bool = false) {
        c.saveGState()
        c.setShouldAntialias(false)
        c.translateBy(x: feet.x.rounded(), y: (feet.y + height).rounded())
        c.scaleBy(x: scale, y: scale)
        fill(c, CGRect(x: -38, y: -8, width: 76, height: 18), 0x16394A)
        fill(c, CGRect(x: -36, y: -3, width: 72, height: 8), 0x348793)
        for x in [-43, 31] {
            fill(c, CGRect(x: CGFloat(x), y: -12, width: 12, height: 24), 0x173C4B)
            fill(c, CGRect(x: CGFloat(x + 2), y: -6, width: 8, height: 12), 0x79E1CC)
        }
        if visor {
            fill(c, CGRect(x: -27, y: -11, width: 54, height: 23), 0x102D3E)
            fill(c, CGRect(x: -23, y: -7, width: 46, height: 16), 0x397A8B)
            fill(c, CGRect(x: -19, y: 2, width: 20, height: 4), 0x9FE5D7)
            fill(c, CGRect(x: -5, y: -19, width: 10, height: 12), 0x203D4B)
        }
        if tank {
            fill(c, CGRect(x: -26, y: -126, width: 52, height: 65), 0x16394A)
            fill(c, CGRect(x: -21, y: -120, width: 42, height: 54), 0xD69547)
            fill(c, CGRect(x: -16, y: -117, width: 10, height: 48), 0xF9CC7A)
            fill(c, CGRect(x: -26, y: -103, width: 52, height: 7), 0x275363)
            fill(c, CGRect(x: -9, y: -64, width: 18, height: 10), 0x83C8B6)
        }
        c.restoreGState()
    }

    private static func fill(_ c: CGContext, _ rect: CGRect, _ color: UInt32, alpha: CGFloat = 1) {
        c.setFillColor(WorldAtmosphere.color(color, alpha: alpha).cgColor)
        c.fill(rect.integral)
    }
}
