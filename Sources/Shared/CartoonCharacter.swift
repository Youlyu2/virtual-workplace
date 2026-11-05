import AppKit
import ImageIO

/// The class lives inside either the app executable or the screen saver plug-in.
/// Bundle.main points at the system host when the screen saver is running.
private final class CharacterResourceAnchor: NSObject {}

enum CartoonCharacter {
    private struct Sprite {
        let image: CGImage
        let height: CGFloat
    }

    private static let sprites: [Sprite]? = loadSprites()
    static var isAvailable: Bool { sprites != nil }

    /// Draws the same three-pose character in both hosts. Returns false if the asset
    /// is unavailable, allowing the renderer to retain a functional native fallback.
    static func draw(in context: CGContext, frame: SceneFrame, activity: EmployeeActivity,
                     time: TimeInterval, sipping: CGFloat, origin: CGPoint = CGPoint(x: 600, y: 125)) -> Bool {
        guard let sprites, sprites.count == 3 else { return false }
        let stand = min(1, max(0, frame.standing))
        let slack = min(1 - stand, max(0, frame.slacking))
        let weights: [CGFloat] = [max(0, 1 - stand - slack), slack, stand]
        let feet = origin

        context.saveGState()
        context.setFillColor(NSColor(srgbRed: 0.22, green: 0.29, blue: 0.24, alpha: 0.11).cgColor)
        context.fillEllipse(in: CGRect(x: feet.x - 61, y: feet.y - 5, width: 122, height: 18))
        context.restoreGState()

        for index in sprites.indices where weights[index] > 0.005 {
            let sprite = sprites[index]
            let breath = time == 0 ? 0 : sin(time * 1.6) * 0.004
            let typing = activity == .working && time > 0 ? sin(time * 7.4) * 0.0018 : 0
            let height = sprite.height * CGFloat(1 + breath)
            let width = height * CGFloat(sprite.image.width) / CGFloat(sprite.image.height)
            context.saveGState()
            context.setAlpha(weights[index])
            context.interpolationQuality = .high
            context.translateBy(x: feet.x, y: feet.y)
            context.rotate(by: CGFloat(typing))
            context.draw(sprite.image, in: CGRect(x: -width / 2, y: 0, width: width, height: height))
            context.restoreGState()
        }

        if activity == .waiting {
            let characterHeight = sprites.enumerated().reduce(CGFloat.zero) { $0 + $1.element.height * weights[$1.offset] }
            drawWaitingBubble(in: context, origin: CGPoint(x: feet.x + 62, y: feet.y + characterHeight - 8), time: time)
        }
        return true
    }

    private static func loadSprites() -> [Sprite]? {
        let bundles = [Bundle(for: CharacterResourceAnchor.self), Bundle.main]
        var candidates = bundles.compactMap { $0.url(forResource: "rear-poses", withExtension: "png", subdirectory: "Characters") }
        // Supports direct swiftc test executables from the repository without
        // tying installed bundles to a developer's absolute workspace path.
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Characters/rear-poses.png"))
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width >= 192, atlas.width <= 8192,
              atlas.height >= 64, atlas.height <= 4096 else { return nil }
        let cellWidth = atlas.width / 3
        let heights: [CGFloat] = [300, 285, 360]
        var result: [Sprite] = []
        for index in 0..<3 {
            guard let cell = atlas.cropping(to: CGRect(x: index * cellWidth, y: 0, width: cellWidth, height: atlas.height)),
                  let image = cropTransparentPadding(cell) else { return nil }
            result.append(Sprite(image: image, height: heights[index]))
        }
        return result
    }

    /// Normalize the bitmap layout before scanning, rather than assuming the PNG
    /// uses RGBA byte order. The cropped CGImage retains its real alpha channel.
    private static func cropTransparentPadding(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The atlas can contain a few pixels of a neighboring pose at a cell
        // edge. Bounding every nontransparent pixel would preserve that ghost.
        // Find the primary connected silhouette, then crop around only its box.
        var visited = [UInt8](repeating: 0, count: width * height)
        var queue: [Int] = []
        var largestCount = 0
        var left = width, right = -1, top = height, bottom = -1
        for seed in 0..<(width * height) where visited[seed] == 0 {
            visited[seed] = 1
            guard bytes[seed * 4 + 3] > 24 else { continue }
            queue.removeAll(keepingCapacity: true)
            queue.append(seed)
            var cursor = 0
            var componentLeft = width, componentRight = -1
            var componentTop = height, componentBottom = -1
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let row = index / width, column = index % width
                componentLeft = min(componentLeft, column); componentRight = max(componentRight, column)
                componentTop = min(componentTop, row); componentBottom = max(componentBottom, row)
                for adjacentRow in max(0, row - 1)...min(height - 1, row + 1) {
                    for adjacentColumn in max(0, column - 1)...min(width - 1, column + 1) {
                        let adjacent = adjacentRow * width + adjacentColumn
                        guard visited[adjacent] == 0 else { continue }
                        visited[adjacent] = 1
                        if bytes[adjacent * 4 + 3] > 24 { queue.append(adjacent) }
                    }
                }
            }
            if queue.count > largestCount {
                largestCount = queue.count
                left = componentLeft; right = componentRight
                top = componentTop; bottom = componentBottom
            }
        }
        guard right >= left, bottom >= top else { return nil }
        let padding = max(2, width / 100)
        left = max(0, left - padding); right = min(width - 1, right + padding)
        top = max(0, top - padding); bottom = min(height - 1, bottom + padding)
        return image.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
    }

    private static func drawWaitingBubble(in context: CGContext, origin: CGPoint, time: TimeInterval) {
        context.saveGState()
        let fill = NSColor(srgbRed: 0.99, green: 0.91, blue: 0.72, alpha: 1).cgColor
        context.setFillColor(fill)
        context.addPath(CGPath(roundedRect: CGRect(x: origin.x, y: origin.y, width: 58, height: 36),
                               cornerWidth: 17, cornerHeight: 17, transform: nil))
        context.fillPath()
        context.beginPath(); context.move(to: CGPoint(x: origin.x + 9, y: origin.y + 5))
        context.addLine(to: CGPoint(x: origin.x + 4, y: origin.y - 7))
        context.addLine(to: CGPoint(x: origin.x + 22, y: origin.y + 5))
        context.closePath(); context.fillPath()
        context.setFillColor(NSColor(srgbRed: 0.50, green: 0.39, blue: 0.24, alpha: 1).cgColor)
        for index in 0..<3 {
            let bounce = time > 0 ? CGFloat(sin(time * 3 + Double(index) * 0.8)) * 1.5 : 0
            context.fillEllipse(in: CGRect(x: origin.x + 15 + CGFloat(index) * 12, y: origin.y + 15 + bounce, width: 5, height: 5))
        }
        context.restoreGState()
    }
}
