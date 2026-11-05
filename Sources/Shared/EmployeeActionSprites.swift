import AppKit
import ImageIO

private final class EmployeeActionResourceAnchor: NSObject {}

/// Manual rear-view gestures. Only the limbs and upper body move; the shoes
/// share the working character's ground line and the room owns the chair.
enum EmployeeActionSprites {
    private struct Sprite {
        var image: CGImage
        var bounds: CGRect
        var centerX: CGFloat
    }
    private struct Atlas {
        var sprites: [Sprite]
        var bodyHeight: CGFloat
    }
    private struct Limb {
        var region: CGPath
        var pivot: CGPoint
        var angle: CGFloat
        var translation: CGPoint = .zero
    }
    private static let atlas: Atlas? = load()
    static var isAvailable: Bool { atlas?.sprites.count == 4 }

    /// `time == 0` is the renderer's reduced-motion contract: the action remains
    /// recognizable as a static pose without arm swings or breathing loops.
    @discardableResult
    static func draw(in c: CGContext, kind: EmployeeAction, progress: CGFloat,
                     time: TimeInterval, feet: CGPoint, pixelSize: CGFloat,
                     walking: EmployeeWalkSample? = nil) -> Bool {
        if kind == .walk {
            let sample = walking ?? AmbientEmployeeMotion.walkSample(progress: progress)
            return PixelWalkingSprites.draw(in: c, direction: sample.direction, distance: sample.distance,
                                            isMoving: time > 0 && sample.isMoving, feet: feet, pixelSize: pixelSize)
        }
        guard let atlas else { return false }
        let index: Int
        switch kind {
        case .coffee: index = 0
        case .stretch: index = 1
        case .wave: index = 2
        case .playWithCat: index = 3
        case .walk: return false // handled by the four-direction walking atlas
        }
        let sprite = atlas.sprites[index]
        let scale = (max(1, pixelSize) / 6) * 310 / atlas.bodyHeight
        let p = max(0, min(1, progress))
        let moving = time > 0
        let phase = moving ? p : 0.5
        let envelope = sin(.pi * phase)
        let step: CGFloat = max(1, pixelSize / 3)
        func snap(_ value: CGFloat) -> CGFloat { (value / step).rounded() * step }
        let imageRect = CGRect(x: (sprite.bounds.minX - sprite.centerX) * scale,
                               y: 0, width: sprite.bounds.width * scale,
                               height: sprite.bounds.height * scale)
        let unit = max(1, pixelSize) / 6
        let bodyPivot = CGPoint(x: 0, y: 132 * unit)
        let upper = CGRect(x: imageRect.minX - 30 * unit, y: -3 * unit,
                           width: imageRect.width + 60 * unit, height: imageRect.height + 35 * unit)
        let rightEdge = max(66 * unit, imageRect.maxX + 4 * unit)
        let legCore = CGRect(x: -66 * unit, y: -3 * unit,
                             width: rightEdge + 66 * unit, height: 135 * unit)
        let motion: CGFloat = moving ? 1 : 0
        var bodyAngle: CGFloat = 0
        var bodyLift: CGFloat = 0
        var limbs: [Limb] = []
        switch kind {
        case .coffee:
            // The authored mug touches the hair silhouette. Keep this upper
            // body intact rather than cutting the cup or dragging hair pixels.
            bodyAngle = 0.035 * envelope * motion
            bodyLift = snap(2 * unit * envelope) * motion
        case .stretch:
            bodyLift = snap(5 * unit * envelope) * motion
            bodyAngle = 0.027 * sin(phase * .pi * 2) * motion
            let sway = 0.075 * sin(phase * .pi * 3) * motion
            limbs = [
                Limb(region: wristRegion(right: false, rect: imageRect, unit: unit),
                     pivot: CGPoint(x: -53 * unit, y: 315 * unit), angle: -sway),
                Limb(region: wristRegion(right: true, rect: imageRect, unit: unit),
                     pivot: CGPoint(x: 53 * unit, y: 315 * unit), angle: sway)
            ]
        case .wave:
            bodyAngle = 0.015 * sin(phase * .pi * 2) * motion
            limbs = [Limb(region: armRegion(right: true, rect: imageRect, unit: unit),
                          pivot: CGPoint(x: 56 * unit, y: 208 * unit),
                          angle: 0.20 * sin(phase * .pi * 8) * motion)]
        case .playWithCat:
            bodyAngle = 0.055 * envelope * motion
            limbs = [Limb(region: toyRegion(rect: imageRect, unit: unit),
                          pivot: CGPoint(x: -51 * unit, y: 194 * unit),
                          angle: 0.10 * sin(phase * .pi * 6) * motion)]
        case .walk: break
        }

        c.saveGState()
        c.setShouldAntialias(false)
        c.interpolationQuality = .none
        c.translateBy(x: feet.x.rounded(), y: feet.y.rounded())
        // Legs and shoes remain anchored while the shoulders perform the action.
        for side in 0..<2 {
            c.saveGState()
            c.clip(to: CGRect(x: side == 0 ? -66 * unit : 0, y: -3 * unit,
                              width: side == 0 ? 66 * unit : rightEdge, height: 158 * unit))
            c.draw(sprite.image, in: imageRect)
            c.restoreGState()
        }

        c.saveGState()
        c.translateBy(x: bodyPivot.x, y: bodyPivot.y + bodyLift)
        c.rotate(by: bodyAngle)
        c.translateBy(x: -bodyPivot.x, y: -bodyPivot.y)
        let upperMask = CGMutablePath()
        upperMask.addRect(upper); upperMask.addRect(legCore)
        c.addPath(upperMask); c.clip(using: .evenOdd)
        // Keep a small original shoulder/wrist joint behind each moving arm.
        // Its texture closes the hinge without retaining the frozen hand.
        for limb in limbs {
            c.saveGState()
            c.clip(to: CGRect(x: limb.pivot.x - 21 * unit, y: limb.pivot.y - 43 * unit,
                              width: 42 * unit, height: 60 * unit))
            c.draw(sprite.image, in: imageRect)
            c.restoreGState()
        }
        // The arm's original pixels are excluded before drawing its rotated
        // copy, preventing a second frozen arm under the moving gesture.
        c.saveGState()
        let body = CGMutablePath()
        body.addRect(upper)
        for limb in limbs { body.addPath(limb.region) }
        c.addPath(body); c.clip(using: .evenOdd)
        c.draw(sprite.image, in: imageRect)
        c.restoreGState()
        for limb in limbs {
            c.saveGState()
            c.translateBy(x: limb.pivot.x + limb.translation.x, y: limb.pivot.y + limb.translation.y)
            c.rotate(by: limb.angle)
            c.translateBy(x: -limb.pivot.x, y: -limb.pivot.y)
            c.addPath(limb.region); c.clip()
            c.draw(sprite.image, in: imageRect)
            c.restoreGState()
        }
        if kind == .coffee { steam(in: c, progress: phase, unit: unit, moving: moving) }
        c.restoreGState()
        c.restoreGState()
        return true
    }

    private static func wristRegion(right: Bool, rect: CGRect, unit: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(x: right ? 36 * unit : rect.minX - 10 * unit,
                            y: 315 * unit,
                            width: right ? rect.maxX : abs(rect.minX) - 26 * unit,
                            height: max(20 * unit, rect.maxY - 305 * unit)))
        return path
    }

    private static func toyRegion(rect: CGRect, unit: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -48 * unit, y: 176 * unit))
        path.addLine(to: CGPoint(x: -48 * unit, y: 220 * unit))
        path.addLine(to: CGPoint(x: rect.minX - 20 * unit, y: 220 * unit))
        path.addLine(to: CGPoint(x: rect.minX - 20 * unit, y: 20 * unit))
        path.addLine(to: CGPoint(x: -65 * unit, y: 20 * unit))
        path.addLine(to: CGPoint(x: -65 * unit, y: 176 * unit))
        path.closeSubpath()
        return path
    }

    private static func steam(in c: CGContext, progress: CGFloat, unit: CGFloat, moving: Bool) {
        let drift = moving ? Int(progress * 14) % 7 : 2
        c.setFillColor(NSColor(srgbRed: 0.96, green: 0.89, blue: 0.68, alpha: 0.7).cgColor)
        for index in 0..<3 {
            let y = CGFloat(255 + index * 8 + drift) * unit
            let x = CGFloat(-67 + (index % 2 == 0 ? 0 : 3)) * unit
            c.fill(CGRect(x: x, y: y, width: 3 * unit, height: 4 * unit).integral)
        }
    }

    /// The head stays inside the central region; outside it, the rear sleeve,
    /// forearm and held cup can move without pulling any face/hair pixels.
    private static func armRegion(right: Bool, rect: CGRect, unit: CGFloat) -> CGPath {
        let sign: CGFloat = right ? 1 : -1
        let reach = max(abs(rect.minX), abs(rect.maxX)) + 24 * unit
        let path = CGMutablePath()
        path.move(to: CGPoint(x: sign * 46 * unit, y: 169 * unit))
        path.addLine(to: CGPoint(x: sign * reach, y: 169 * unit))
        path.addLine(to: CGPoint(x: sign * reach, y: rect.maxY + 24 * unit))
        path.addLine(to: CGPoint(x: sign * 65 * unit, y: rect.maxY + 24 * unit))
        path.addLine(to: CGPoint(x: sign * 65 * unit, y: 222 * unit))
        path.addLine(to: CGPoint(x: sign * 46 * unit, y: 222 * unit))
        path.closeSubpath()
        return path
    }

    private static func load() -> Atlas? {
        let bundles = [Bundle(for: EmployeeActionResourceAnchor.self), Bundle.main]
        var candidates = bundles.compactMap {
            $0.url(forResource: "employee-actions", withExtension: "png", subdirectory: "Room")
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Room/employee-actions.png"))
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width >= 256, image.width <= 8192,
              image.height >= 64, image.height <= 4096 else { return nil }
        let cuts = columnCuts(image)
        var sprites: [Sprite] = []
        for index in 0..<4 {
            guard let cell = image.cropping(to: CGRect(x: cuts[index], y: 0, width: cuts[index + 1] - cuts[index], height: image.height)),
                  let sprite = decode(cell) else { return nil }
            sprites.append(sprite)
        }
        // The normal-height coffee and cat poses anchor the common scale.
        // Raised hands in the stretching/waving columns never shrink the body.
        let bodyHeight = (sprites[0].bounds.height + sprites[3].bounds.height) / 2
        guard bodyHeight > 20 else { return nil }
        return Atlas(sprites: sprites, bodyHeight: bodyHeight)
    }

    /// Generated props can extend slightly across nominal equal-cell borders.
    /// Split at the nearest genuinely empty column so no dangling toy leaks
    /// into the waving pose and no authored pixels are cut away.
    private static func columnCuts(_ image: CGImage) -> [Int] {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return [0, width / 4, width / 2, width * 3 / 4, width]
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var occupied = [Bool](repeating: false, count: width)
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] >= 160 { occupied[x] = true }
        }
        var result = [0]
        let radius = max(8, width / 20)
        for index in 1..<4 {
            let target = width * index / 4
            let choices = (max(result.last! + 1, target - radius)..<min(width - 1, target + radius))
                .filter { x in !occupied[x] && !occupied[x - 1] && !occupied[x + 1] }
            result.append(choices.min(by: { abs($0 - target) < abs($1 - target) }) ?? target)
        }
        result.append(width)
        return result
    }

    private static func decode(_ image: CGImage) -> Sprite? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var left = width, right = -1, top = height, bottom = -1
        var lowerLeft = width, lowerRight = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4, alpha = Int(bytes[i + 3])
                if alpha < 160 {
                    bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0
                } else {
                    for channel in 0..<3 {
                        bytes[i + channel] = UInt8(min(255, (Int(bytes[i + channel]) * 255 + alpha / 2) / alpha))
                    }
                    bytes[i + 3] = 255
                    left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        guard right >= left, bottom >= top, let cleaned = context.makeImage() else { return nil }
        // The dangling cat toy reaches below the knees. Only the shoe band is
        // a reliable body centre, never the full lower third of the silhouette.
        for y in (top + (bottom - top) * 85 / 100)...bottom {
            for x in left...right where bytes[(y * width + x) * 4 + 3] >= 160 {
                lowerLeft = min(lowerLeft, x); lowerRight = max(lowerRight, x)
            }
        }
        let bounds = CGRect(x: max(0, left - 2), y: max(0, top - 2),
                            width: min(width - max(0, left - 2), right - left + 5),
                            height: min(height - max(0, top - 2), bottom - top + 5))
        guard let cropped = cleaned.cropping(to: bounds) else { return nil }
        let center = lowerRight >= lowerLeft ? CGFloat(lowerLeft + lowerRight) / 2 : CGFloat(width) / 2
        return Sprite(image: cropped, bounds: bounds, centerX: center)
    }
}
