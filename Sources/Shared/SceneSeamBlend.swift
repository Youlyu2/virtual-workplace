import AppKit

/// A top-down stone threshold on the same flat ground grid as the garden path.
/// The two hosts crop one world-space strip; no independent pillar, perspective
/// stair or foreground vine is placed over the room/outdoor boundary.
enum SceneSeamBlend {
    static let referenceSize = CGSize(width: 1672, height: 941)
    static let passageRange: ClosedRange<CGFloat> = 110...220
    static let thresholdWidth: CGFloat = 32
    private static let textureBounds = CGRect(x: -thresholdWidth / 2,
        y: passageRange.lowerBound, width: thresholdWidth,
        height: passageRange.upperBound - passageRange.lowerBound)
    private static let artwork = makeArtwork()
    private static let cacheLock = NSLock()
    private static var cachedGrade: Grade?
    private static var cachedArtwork: CGImage?

    static var isAvailable: Bool { artwork != nil }

    static func draw(in c: CGContext, bounds: CGRect, world: SceneWorld,
                     at date: Date, viewport: WorldViewport) {
        guard !viewport.seams.isEmpty, bounds.width > 0, bounds.height > 0,
              let image = gradedArtwork(world: world, at: date) else { return }
        c.saveGState(); c.clip(to: bounds)
        c.concatenate(viewport.mapping(into: bounds))
        c.interpolationQuality = .none
        c.setShouldAntialias(false)
        for seam in viewport.seams {
            let scale = (seam.upperY - seam.lowerY) / referenceSize.height
            let reach = CGRect(x: seam.boundaryX - thresholdWidth * scale / 2,
                y: seam.lowerY + passageRange.lowerBound * scale,
                width: thresholdWidth * scale,
                height: (passageRange.upperBound - passageRange.lowerBound) * scale)
            guard reach.intersects(viewport.display) else { continue }
            c.saveGState()
            c.translateBy(x: seam.boundaryX, y: seam.lowerY)
            c.scaleBy(x: seam.roomOnRight ? scale : -scale, y: scale)
            c.draw(image, in: textureBounds)
            c.restoreGState()
        }
        c.restoreGState()
    }

    private struct Grade: Equatable {
        let night: Int
        let sunset: Int
        let weather: WorldWeather

        init(world: SceneWorld, at date: Date) {
            let environment = world.environment(at: date)
            night = Int((max(0, min(1, environment.darkness)) * 128).rounded())
            sunset = Int((max(0, min(1, environment.sunset)) * 128).rounded())
            weather = world.weather
        }
    }

    private static func gradedArtwork(world: SceneWorld, at date: Date) -> CGImage? {
        guard let artwork else { return nil }
        let grade = Grade(world: world, at: date)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if cachedGrade == grade, let cachedArtwork { return cachedArtwork }
        guard let c = bitmap(width: artwork.width, height: artwork.height) else { return artwork }
        let bounds = CGRect(x: 0, y: 0, width: artwork.width, height: artwork.height)
        c.draw(artwork, in: bounds)
        // Source-atop keeps the rest of the room and landscape untouched.
        c.setBlendMode(.sourceAtop)
        func tint(_ color: UInt32, alpha: CGFloat) {
            guard alpha > 0 else { return }
            c.setFillColor(WorldAtmosphere.color(color, alpha: alpha).cgColor); c.fill(bounds)
        }
        let darkness = CGFloat(grade.night) / 128
        tint(0xF5AB68, alpha: CGFloat(grade.sunset) / 128 * 0.16 * (1 - darkness * 0.5))
        tint(0x152845, alpha: darkness * 0.64)
        switch grade.weather {
        case .clear: break
        case .cloudy: tint(0x6A7E84, alpha: 0.08)
        case .rain: tint(0x425F72, alpha: 0.14)
        case .snow: tint(0xB8D1D9, alpha: 0.08)
        case .thunderstorm: tint(0x344B63, alpha: 0.22)
        }
        let result = c.makeImage()
        cachedGrade = grade; cachedArtwork = result
        return result ?? artwork
    }

    private static func makeArtwork() -> CGImage? {
        let width = Int(textureBounds.width), height = Int(textureBounds.height)
        guard let c = bitmap(width: width, height: height) else { return nil }
        c.setShouldAntialias(false)
        let tileHeight = CGFloat(height) / 3
        for row in 0..<3 {
            let y0 = (CGFloat(row) * tileHeight).rounded()
            let y1 = (CGFloat(row + 1) * tileHeight).rounded()
            c.setFillColor(WorldAtmosphere.color(row == 1 ? 0xC5B69B : 0xCEBEA2).cgColor)
            c.fill(CGRect(x: 0, y: y0, width: CGFloat(width), height: y1 - y0))
            // These are tile grout lines on a flat surface, not raised risers.
            if row > 0 {
                c.setFillColor(WorldAtmosphere.color(0x8F806B).cgColor)
                c.fill(CGRect(x: 0, y: y0, width: CGFloat(width), height: 2))
            }
            c.setFillColor(WorldAtmosphere.color(0xDDCDB2, alpha: 0.62).cgColor)
            for grain in 0..<5 {
                let x = CGFloat(4 + (grain * 7 + row * 3) % 23)
                let y = y0 + 6 + CGFloat((grain * 11 + row * 5) % 23)
                c.fill(CGRect(x: x, y: y, width: 2, height: 1))
            }
        }
        return c.makeImage()
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
