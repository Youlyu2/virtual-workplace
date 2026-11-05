import AppKit
import ImageIO

private final class EmployeeSpriteResourceAnchor: NSObject {}

/// Decodes the production pixel-art atlas once for each host bundle. All cleanup
/// happens in memory: the authored PNG remains untouched in project resources.
enum PixelEmployeeSprites {
    private static let images: [CGImage]? = load()
    private static let workingBodies: [CGImage]? = {
        guard let images else { return nil }
        return [armFreeBody(images[0], standing: false), armFreeBody(images[1], standing: true)].compactMap { $0 }
    }()
    private static let sleepingHead: CGImage? = {
        guard let body = images?[1],
              let top = body.cropping(to: CGRect(x: 0, y: 0, width: body.width,
                                                 height: Int(CGFloat(body.height) * 0.315))) else { return nil }
        // The top 31.5% ends above the raised hands. Trimming its transparent
        // columns retains only the rear hair, with no arm or clothing fragment.
        return decodeSprite(top)
    }()
    static var isAvailable: Bool { images?.count == 3 }

    static func drawWorking(in c: CGContext, standing: CGFloat, time: TimeInterval,
                            activity: EmployeeActivity, feet: CGPoint, pixelSize: CGFloat) -> Bool {
        guard let workingBodies, workingBodies.count == 2 else { return false }
        let amount = max(0, min(1, standing))
        let scale = max(1, pixelSize) / 6
        let motion = WorkInputMotion.sample(time: time, activity: activity)

        // The transparency group applies the caller's global opacity once. It
        // keeps the room's sleeping fade independent of the two pose weights.
        c.saveGState()
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        // The arms are behind the torso and rear hair. That preserves the
        // camera's depth: fingers peek beside the head instead of being pasted
        // onto the back of it. Body, chair and shoes never bob with a keystroke.
        drawArms(in: c, amount: amount, motion: motion, feet: feet, scale: scale)
        if amount < 0.999 {
            c.saveGState(); c.setAlpha(1 - amount)
            draw(workingBodies[0], in: c, feet: feet, height: 270 * scale)
            c.restoreGState()
        }
        if amount > 0.001 {
            c.saveGState(); c.setAlpha(amount)
            draw(workingBodies[1], in: c, feet: feet, height: 310 * scale)
            c.restoreGState()
        }
        c.endTransparencyLayer()
        c.restoreGState()
        return true
    }

    private static func drawArms(in c: CGContext, amount: CGFloat, motion: WorkInputMotion,
                                 feet: CGPoint, scale: CGFloat) {
        c.saveGState()
        c.setShouldAntialias(false)
        c.translateBy(x: feet.x.rounded(), y: feet.y.rounded())
        c.scaleBy(x: scale, y: scale)
        let rise = 40 * amount
        let mix = motion.rightHandMix
        let left = CGPoint(x: -57, y: 192 + rise - motion.leftPress * 1.2)
        let rightKey = CGPoint(x: 54, y: 192 + rise - motion.rightPress * 1.2)
        let mouse = CGPoint(x: 115 + motion.mouseOffset.x, y: 189 + rise + motion.mouseOffset.y - motion.click)
        let right = CGPoint(x: rightKey.x + (mouse.x - rightKey.x) * mix,
                            y: rightKey.y + (mouse.y - rightKey.y) * mix)
        let shoulderY = 165 + amount * 33
        let elbowY = 151 + amount * 43
        sleeve(in: c, shoulder: CGPoint(x: -35, y: shoulderY),
               elbow: CGPoint(x: -52, y: elbowY), wrist: CGPoint(x: left.x, y: left.y - 6))
        sleeve(in: c, shoulder: CGPoint(x: 35, y: shoulderY),
               elbow: CGPoint(x: 53 + 31 * mix, y: elbowY - 7 * mix),
               wrist: CGPoint(x: right.x - 2 * mix, y: right.y - 6))
        hand(in: c, center: left, pressed: motion.leftPress, mouse: false, click: 0)
        hand(in: c, center: right, pressed: motion.rightPress * (1 - mix), mouse: mix > 0.65, click: motion.click)
        c.restoreGState()
    }

    /// Rasterized two-joint sleeves retain the room's square pixel edges while
    /// keeping a continuous shoulder/elbow/wrist connection at every phase.
    private static func sleeve(in c: CGContext, shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) {
        let radius: CGFloat = 8
        let bounds = CGRect(x: min(shoulder.x, elbow.x, wrist.x) - radius,
                            y: min(shoulder.y, elbow.y, wrist.y) - radius,
                            width: max(shoulder.x, elbow.x, wrist.x) - min(shoulder.x, elbow.x, wrist.x) + radius * 2,
                            height: max(shoulder.y, elbow.y, wrist.y) - min(shoulder.y, elbow.y, wrist.y) + radius * 2)
        func nearest(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(1, dx * dx + dy * dy)))
            return CGPoint(x: a.x + dx * t, y: a.y + dy * t)
        }
        for y in stride(from: floor(bounds.minY / 2) * 2, through: bounds.maxY, by: 2) {
            for x in stride(from: floor(bounds.minX / 2) * 2, through: bounds.maxX, by: 2) {
                let p = CGPoint(x: x + 1, y: y + 1)
                let a = nearest(p, shoulder, elbow), b = nearest(p, elbow, wrist)
                let da = hypot(p.x - a.x, p.y - a.y), db = hypot(p.x - b.x, p.y - b.y)
                let joint = da < db ? a : b
                let distance = min(da, db)
                guard distance <= radius else { continue }
                let color: UInt32
                if distance > radius - 2 { color = 0x273B24 }
                else if p.x < joint.x - 2 || p.y > joint.y + 5 { color = 0x7A9E3C }
                else if p.x > joint.x + 4 || p.y < joint.y - 5 { color = 0x3B602A }
                else { color = 0x5C8533 }
                pixel(c, CGRect(x: x, y: y, width: 2, height: 2), color)
            }
        }
        // A small ribbed cuff meets the skin without a bare disconnected wrist.
        pixel(c, CGRect(x: wrist.x - 7, y: wrist.y - 4, width: 14, height: 6), 0x304D27)
        pixel(c, CGRect(x: wrist.x - 5, y: wrist.y, width: 10, height: 2), 0x90AA49)
    }

    private static func hand(in c: CGContext, center: CGPoint, pressed: CGFloat, mouse: Bool, click: CGFloat) {
        let x = center.x.rounded(), y = center.y.rounded()
        pixel(c, CGRect(x: x - 9, y: y - 6, width: 18, height: 12), 0x65482B)
        pixel(c, CGRect(x: x - 7, y: y - 4, width: 14, height: 8), 0xDDB47C)
        pixel(c, CGRect(x: x - 5, y: y - 1, width: 10, height: 5), 0xF2D39A)
        let fingerY = y + 2 - (mouse ? click : pressed).rounded()
        for offset in [-5, -1, 3] {
            pixel(c, CGRect(x: x + CGFloat(offset), y: fingerY, width: 3, height: mouse ? 3 : 4), 0xF7DFA9)
        }
        pixel(c, CGRect(x: x + (mouse ? -9 : 6), y: y - 3, width: 3, height: 5), 0xD0A36B)
    }

    private static func pixel(_ c: CGContext, _ rect: CGRect, _ color: UInt32) {
        c.setFillColor(CGColor(red: CGFloat((color >> 16) & 255) / 255,
                              green: CGFloat((color >> 8) & 255) / 255,
                              blue: CGFloat(color & 255) / 255, alpha: 1))
        c.fill(rect.integral)
    }

    /// Remove only the two raised sleeves/hands from the decoded production
    /// pose. Rear hair and the chair remain verbatim, and the source PNG is not
    /// edited. Reaching arms are rebuilt as a separate animated layer.
    private static func armFreeBody(_ image: CGImage, standing: Bool) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let displayHeight: CGFloat = standing ? 310 : 270
        let scale = displayHeight / CGFloat(height), displayWidth = CGFloat(width) * scale
        let neck: CGFloat = standing ? 200 : 173
        // Trace the connected rear head before removing the raised arms. Hair
        // has dark outline pixels as well as brown fill, so retaining individual
        // colors would leave transparent pinholes along its lower edge.
        var head = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        func belongsToHead(_ row: Int, _ column: Int) -> Bool {
            let index = (row * width + column) * 4
            let y = (CGFloat(height - row) - 0.5) * scale
            let x = (CGFloat(column) + 0.5) * scale - displayWidth / 2
            let headWidth = min(CGFloat(61), 26 + max(0, y - neck) * 1.45)
            guard y >= neck - 2, abs(x) <= headWidth, bytes[index + 3] > 0 else { return false }
            let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
            // Exclude green hoodie cloth while allowing dark hair outlines,
            // highlights and the two tiny ears that touch the hair silhouette.
            return !(g > r * 108 / 100 && g > b * 115 / 100)
        }
        for row in 0..<height {
            let y = (CGFloat(height - row) - 0.5) * scale
            guard y > neck + 45 else { continue }
            for column in 0..<width where belongsToHead(row, column) {
                let i = row * width + column
                head[i] = true; queue.append(i)
            }
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]; cursor += 1
            let row = index / width, column = index % width
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nextRow = row + dy, nextColumn = column + dx
                    guard nextRow >= 0, nextRow < height, nextColumn >= 0, nextColumn < width else { continue }
                    let next = nextRow * width + nextColumn
                    if !head[next], belongsToHead(nextRow, nextColumn) {
                        head[next] = true; queue.append(next)
                    }
                }
            }
        }
        for row in 0..<height {
            for column in 0..<width {
                let x = (CGFloat(column) + 0.5) * scale - displayWidth / 2
                let y = (CGFloat(height - row) - 0.5) * scale
                let minY: CGFloat = standing ? 144 : 133
                let distance = abs(x)
                guard y > minY, y < neck + 26 else { continue }
                // The old raised fists contain the same warm brown outline as
                // the hair. A color-only test therefore retained little rings
                // beside the neck. Preserve the actual rear-head contour and
                // hoodie separately, rather than mistaking those rings for ears.
                let i = (row * width + column) * 4
                let isHead = head[row * width + column]
                let r = Int(bytes[i]), g = Int(bytes[i + 1])
                let isHoodie = y < neck + 4 && distance <= (standing ? 43 : 44)
                    && (y < neck - 4 || distance < 28 || g >= r)
                if !isHead && !isHoodie {
                    bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0
                }
            }
        }
        // Small disconnected outline islands came from the old sleeve/fist
        // cut. They are never part of the connected head or torso silhouette.
        var seen = [Bool](repeating: false, count: width * height)
        for seed in 0..<(width * height) where !seen[seed] && bytes[seed * 4 + 3] > 0 {
            var component = [seed]; seen[seed] = true
            var at = 0
            while at < component.count {
                let index = component[at]; at += 1
                let row = index / width, column = index % width
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nextRow = row + dy, nextColumn = column + dx
                    guard nextRow >= 0, nextRow < height, nextColumn >= 0, nextColumn < width else { continue }
                    let next = nextRow * width + nextColumn
                    if !seen[next], bytes[next * 4 + 3] > 0 {
                        seen[next] = true; component.append(next)
                    }
                }
            }
            if component.count < 128 {
                for index in component { for channel in 0..<4 { bytes[index * 4 + channel] = 0 } }
            }
        }
        return context.makeImage()
    }

    static func drawEmptyChair(in c: CGContext, standing: CGFloat, feet: CGPoint, pixelSize: CGFloat) {
        guard let images, images.count == 3 else { return }
        let scale = max(1, pixelSize) / 6
        let position = CGPoint(x: feet.x + 260 * max(0, min(1, standing)) * scale, y: feet.y)
        draw(images[2], in: c, feet: position, height: 160 * scale)
    }

    static func drawSleeping(in c: CGContext, headCenter: CGPoint, pixelSize: CGFloat) -> Bool {
        guard let head = sleepingHead else { return false }
        let unit = max(1, pixelSize)
        let scale = min(18 * unit / CGFloat(head.width), 13 * unit / CGFloat(head.height))
        let size = CGSize(width: (CGFloat(head.width) * scale).rounded(),
                          height: (CGFloat(head.height) * scale).rounded())
        c.saveGState()
        c.setShouldAntialias(false)
        c.interpolationQuality = .none
        c.draw(head, in: CGRect(x: (headCenter.x - size.width / 2).rounded(),
                               y: (headCenter.y - size.height / 2).rounded(),
                               width: size.width, height: size.height))
        c.restoreGState()
        return true
    }

    private static func draw(_ image: CGImage, in c: CGContext, feet: CGPoint, height: CGFloat) {
        let width = height * CGFloat(image.width) / CGFloat(image.height)
        c.saveGState()
        c.setShouldAntialias(false)
        c.interpolationQuality = .none
        c.draw(image, in: CGRect(x: (feet.x - width / 2).rounded(), y: feet.y.rounded(),
                                width: width.rounded(), height: height.rounded()))
        c.restoreGState()
    }

    private static func load() -> [CGImage]? {
        let bundles = [Bundle(for: EmployeeSpriteResourceAnchor.self), Bundle.main]
        var candidates = bundles.compactMap {
            $0.url(forResource: "employee-kit", withExtension: "png", subdirectory: "Room")
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Room/employee-kit.png"))
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width >= 192, atlas.width <= 8192,
              atlas.height >= 64, atlas.height <= 4096 else { return nil }
        let cellWidth = atlas.width / 3
        var result: [CGImage] = []
        for column in 0..<3 {
            guard let cell = atlas.cropping(to: CGRect(x: column * cellWidth, y: 0,
                                                      width: cellWidth, height: atlas.height)),
                  let sprite = decodeSprite(cell) else { return nil }
            result.append(sprite)
        }
        return result
    }

    private static func decodeSprite(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var left = width, right = -1, top = height, bottom = -1
        for row in 0..<height {
            for column in 0..<width {
                let index = (row * width + column) * 4
                let alpha = Int(bytes[index + 3])
                // The source includes a very low-opacity colored studio glow.
                // A binary silhouette suits the pixel art and prevents that glow
                // tinting arbitrary room backgrounds, especially pale bed linen.
                if alpha < 160 {
                    bytes[index] = 0; bytes[index + 1] = 0
                    bytes[index + 2] = 0; bytes[index + 3] = 0
                    continue
                }
                for channel in 0..<3 {
                    bytes[index + channel] = UInt8(min(255, (Int(bytes[index + channel]) * 255 + alpha / 2) / alpha))
                }
                bytes[index + 3] = 255
                if alpha >= 192 {
                    left = min(left, column); right = max(right, column)
                    top = min(top, row); bottom = max(bottom, row)
                }
            }
        }
        guard left <= right, top <= bottom, let cleaned = bitmap.makeImage() else { return nil }
        let padding = 2
        left = max(0, left - padding); right = min(width - 1, right + padding)
        top = max(0, top - padding); bottom = min(height - 1, bottom + padding)
        return cleaned.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
    }
}
