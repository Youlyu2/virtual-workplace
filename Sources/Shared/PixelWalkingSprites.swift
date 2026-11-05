import AppKit
import ImageIO

private final class WalkingSpriteResourceAnchor: NSObject {}

/// Authored front, profile and rear walk frames. Movement selects a frame by
/// distance travelled; stopping plants the feet instead of running in place.
enum PixelWalkingSprites {
    private struct Sprite {
        var image: CGImage
        var width: CGFloat
        var height: CGFloat
        var anchorX: CGFloat
    }
    private struct Atlas {
        var rows: [[Sprite]]
        var referenceHeight: CGFloat
    }
    private static let atlas: Atlas? = load()
    static var isAvailable: Bool { atlas?.rows.count == 4 && atlas?.rows.allSatisfy { $0.count == 4 } == true }

    @discardableResult
    static func draw(in c: CGContext, direction: PixelWalkDirection, distance: CGFloat,
                     isMoving: Bool, feet: CGPoint, pixelSize: CGFloat,
                     targetHeight: CGFloat? = nil) -> Bool {
        guard let atlas, feet.x.isFinite, feet.y.isFinite else { return false }
        let row: Int
        switch direction {
        case .down: row = 0
        case .left: row = 1
        case .right: row = 2
        case .up: row = 3
        }
        let travel = distance.isFinite && distance > 0 ? distance : 0
        // Modulo before Int conversion keeps even enormous diagnostic clocks
        // bounded. One stride spans 80 world pixels, with a contact every 40.
        let frame = isMoving ? Int((travel.truncatingRemainder(dividingBy: 80) / 20).rounded(.down)) : 0
        let sprite = atlas.rows[row][frame]
        let unit = pixelSize.isFinite ? max(1, pixelSize) / 6 : 1
        let scale = targetHeight.flatMap { $0.isFinite && $0 > 0 ? $0 / atlas.referenceHeight : nil }
            ?? 310 * unit / atlas.referenceHeight
        let width = (sprite.width * scale).rounded()
        let height = (sprite.height * scale).rounded()
        c.saveGState()
        c.setShouldAntialias(false)
        c.interpolationQuality = .none
        c.draw(sprite.image, in: CGRect(x: (feet.x - sprite.anchorX * scale).rounded(), y: feet.y.rounded(),
                                        width: width, height: height))
        c.restoreGState()
        return true
    }

    private static func load() -> Atlas? {
        let bundles = [Bundle(for: WalkingSpriteResourceAnchor.self), Bundle.main]
        var candidates = bundles.compactMap {
            $0.url(forResource: "employee-walk", withExtension: "png", subdirectory: "Room")
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Room/employee-walk.png"))
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width >= 256, image.width <= 8192,
              image.height >= 256, image.height <= 8192,
              let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = image.width, height = image.height
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var occupied = [Bool](repeating: false, count: height)
        // The PNG retains true alpha. Hard pixel silhouettes remove only faint
        // colored fringes while the authored source remains unchanged on disk.
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let alpha = Int(bytes[i + 3])
                if alpha < 160 {
                    bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0
                } else {
                    for channel in 0..<3 {
                        bytes[i + channel] = UInt8(min(255, (Int(bytes[i + channel]) * 255 + alpha / 2) / alpha))
                    }
                    bytes[i + 3] = 255
                    occupied[y] = true
                }
            }
        }
        guard let cleaned = bitmap.makeImage() else { return nil }
        // Authored rows have clear transparent gaps, which can be a few pixels
        // away from exact quarter divisions. Split in those gaps so no tuft of
        // the next row leaks into another sprite or gets cut off.
        var rowCuts = [0]
        for index in 1..<4 {
            let target = height * index / 4
            let radius = height / 12
            var gaps: [(Int, Int)] = []
            var begin: Int?
            for y in max(rowCuts.last! + 1, target - radius)..<min(height - 1, target + radius) {
                if !occupied[y] { if begin == nil { begin = y } }
                else if let start = begin { gaps.append((start, y - 1)); begin = nil }
            }
            if let start = begin { gaps.append((start, min(height - 2, target + radius - 1))) }
            let best = gaps.filter { $0.1 - $0.0 >= 3 }
                .min { abs(($0.0 + $0.1) / 2 - target) < abs(($1.0 + $1.1) / 2 - target) }
            rowCuts.append(best.map { ($0.0 + $0.1) / 2 } ?? target)
        }
        rowCuts.append(height)
        var rows: [[Sprite]] = []
        for row in 0..<4 {
            var sprites: [Sprite] = []
            for column in 0..<4 {
                let minX = width * column / 4, maxX = width * (column + 1) / 4
                var left = maxX, right = minX - 1, top = rowCuts[row + 1], bottom = rowCuts[row] - 1
                for y in rowCuts[row]..<rowCuts[row + 1] {
                    for x in minX..<maxX where bytes[(y * width + x) * 4 + 3] > 0 {
                        left = min(left, x); right = max(right, x)
                        top = min(top, y); bottom = max(bottom, y)
                    }
                }
                guard left <= right, top <= bottom,
                      let crop = cleaned.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) else { return nil }
                // A side stride widens the legs. Anchor to the rear/front head
                // silhouette instead of recentering the entire bounding box,
                // which would make the torso rock sideways on every frame.
                var headLeft = right, headRight = left
                let headBottom = min(bottom, top + Int(CGFloat(bottom - top + 1) * 0.40))
                for y in top...headBottom {
                    for x in left...right where bytes[(y * width + x) * 4 + 3] > 0 {
                        headLeft = min(headLeft, x); headRight = max(headRight, x)
                    }
                }
                let anchorX = CGFloat(headLeft + headRight) / 2 - CGFloat(left)
                sprites.append(Sprite(image: crop, width: CGFloat(crop.width), height: CGFloat(crop.height), anchorX: anchorX))
            }
            rows.append(sprites)
        }
        // Use one shared scale for all frames; never resize a raised foot or a
        // wider side stride to a different head/body scale.
        let referenceHeight = rows.flatMap { $0 }.map(\.height).max() ?? 0
        guard referenceHeight > 20 else { return nil }
        return Atlas(rows: rows, referenceHeight: referenceHeight)
    }
}
