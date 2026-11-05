import AppKit
import ImageIO

private final class PendingVisitorResourceAnchor: NSObject {}

/// Eight separately drawn visitors. Each row owns front/profile/rear poses;
/// only the right profile is mirrored. The employee's atlas is never reused.
enum PendingVisitorSprites {
    private struct Sprite {
        let image: CGImage
        let anchorX: CGFloat
    }
    private struct Visitor {
        let poses: [Sprite]
        let referenceHeight: CGFloat
    }
    private static let visitors: [Visitor]? = load()
    static var isAvailable: Bool { visitors?.count == 8 && visitors?.allSatisfy { $0.poses.count == 6 } == true }

    @discardableResult
    static func draw(in c: CGContext, variant: Int, direction: PixelWalkDirection,
                     distance: CGFloat, isMoving: Bool, feet: CGPoint,
                     targetHeight: CGFloat) -> Bool {
        guard let visitors, feet.x.isFinite, feet.y.isFinite,
              targetHeight.isFinite, targetHeight > 0, targetHeight <= 8192 else { return false }
        let visitor = visitors[((variant % 8) + 8) % 8]
        let travel = distance.isFinite && distance > 0 ? distance : 0
        // Slow, distance-driven steps. A pause always settles into a neutral
        // pose; separate hosts obtain the same stride from the shared route.
        let phase = isMoving ? Int(travel.truncatingRemainder(dividingBy: 40) / 10) : 0
        let contact = phase == 1 || phase == 3
        let pose: Int
        switch direction {
        case .down: pose = contact ? 1 : 0
        case .left, .right: pose = contact ? 3 : 2
        case .up: pose = contact ? 5 : 4
        }
        let sprite = visitor.poses[pose]
        let scale = targetHeight / visitor.referenceHeight
        let anchor = CGPoint(x: feet.x.rounded(), y: feet.y.rounded())
        let rect = CGRect(x: -sprite.anchorX * scale, y: 0,
                          width: CGFloat(sprite.image.width) * scale,
                          height: CGFloat(sprite.image.height) * scale).integral
        c.saveGState()
        c.setShouldAntialias(false); c.interpolationQuality = .none
        c.translateBy(x: anchor.x, y: anchor.y)
        if direction == .right { c.scaleBy(x: -1, y: 1) }
        if phase == 3 && (direction == .down || direction == .up) {
            // Reverse only the lower leg contact. Hair, glasses, braid, hat
            // and asymmetric clothing stay on their authored side.
            let legTop = (targetHeight * 0.27).rounded()
            c.saveGState()
            c.clip(to: CGRect(x: -targetHeight, y: legTop, width: targetHeight * 2, height: targetHeight))
            c.draw(sprite.image, in: rect)
            c.restoreGState()
            c.saveGState()
            c.clip(to: CGRect(x: -targetHeight, y: 0, width: targetHeight * 2, height: legTop))
            c.scaleBy(x: -1, y: 1)
            c.draw(sprite.image, in: rect)
            c.restoreGState()
        } else {
            c.draw(sprite.image, in: rect)
        }
        c.restoreGState()
        return true
    }

    private static func load() -> [Visitor]? {
        let bundles = [Bundle(for: PendingVisitorResourceAnchor.self), Bundle.main]
        var candidates = bundles.compactMap {
            $0.url(forResource: "pending-visitors", withExtension: "png", subdirectory: "Room")
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Room/pending-visitors.png"))
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              (256...8192).contains(image.width), (256...8192).contains(image.height),
              let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = image.width, height = image.height
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var occupiedRows = [Bool](repeating: false, count: height)
        // Generated PNG alpha is real. Remove its faint alpha fringe at decode
        // time only; never key out dark hair or recolor the authored asset.
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4, alpha = Int(bytes[i + 3])
                if alpha < 160 {
                    for channel in 0..<4 { bytes[i + channel] = 0 }
                } else {
                    for channel in 0..<3 {
                        bytes[i + channel] = UInt8(min(255, (Int(bytes[i + channel]) * 255 + alpha / 2) / alpha))
                    }
                    bytes[i + 3] = 255; occupiedRows[y] = true
                }
            }
        }
        guard let cleaned = bitmap.makeImage() else { return nil }
        let rowCuts = cuts(occupancy: occupiedRows, count: 8)
        var result: [Visitor] = []
        for row in 0..<8 {
            var occupiedColumns = [Bool](repeating: false, count: width)
            for y in rowCuts[row]..<rowCuts[row + 1] {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 0 { occupiedColumns[x] = true }
            }
            // The atlas's clear gaps, not ideal equal cell centres, decide
            // boundaries so a wide straw hat or arm is never sliced away.
            let columnCuts = cuts(occupancy: occupiedColumns, count: 6)
            var poses: [Sprite] = []
            for column in 0..<6 {
                var left = width, right = -1, top = height, bottom = -1
                for y in rowCuts[row]..<rowCuts[row + 1] {
                    for x in columnCuts[column]..<columnCuts[column + 1] where bytes[(y * width + x) * 4 + 3] > 0 {
                        left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                    }
                }
                guard left <= right, top <= bottom,
                      let crop = cleaned.cropping(to: CGRect(x: left, y: top,
                        width: right - left + 1, height: bottom - top + 1)) else { return nil }
                var headLeft = right, headRight = left
                let headBottom = min(bottom, top + Int(CGFloat(bottom - top + 1) * 0.40))
                for y in top...headBottom {
                    for x in left...right where bytes[(y * width + x) * 4 + 3] > 0 {
                        headLeft = min(headLeft, x); headRight = max(headRight, x)
                    }
                }
                poses.append(Sprite(image: crop, anchorX: CGFloat(headLeft + headRight) / 2 - CGFloat(left)))
            }
            let reference = CGFloat(poses.map { $0.image.height }.max() ?? 0)
            guard reference > 20 else { return nil }
            result.append(Visitor(poses: poses, referenceHeight: reference))
        }
        return result
    }

    private static func cuts(occupancy: [Bool], count: Int) -> [Int] {
        var result = [0]
        for index in 1..<count {
            let target = occupancy.count * index / count
            let radius = occupancy.count / (count * 2)
            let lower = max(result.last! + 1, target - radius), upper = min(occupancy.count - 1, target + radius)
            var gaps: [ClosedRange<Int>] = [], start: Int?
            for i in lower...upper {
                if !occupancy[i] { if start == nil { start = i } }
                else if let s = start { gaps.append(s...(i - 1)); start = nil }
            }
            if let s = start { gaps.append(s...upper) }
            let best = gaps.filter { $0.count >= 3 }.min {
                abs(($0.lowerBound + $0.upperBound) / 2 - target) < abs(($1.lowerBound + $1.upperBound) / 2 - target)
            }
            result.append(best.map { ($0.lowerBound + $0.upperBound) / 2 } ?? target)
        }
        result.append(occupancy.count)
        return result
    }
}
