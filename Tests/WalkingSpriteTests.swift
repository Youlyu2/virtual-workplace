import AppKit
import ImageIO

/// Uses the shipped atlas and renderer, never a fake sprite or user state.
@main
struct WalkingSpriteTests {
    private static var checks = 0
    private static let directions: [PixelWalkDirection] = [.down, .left, .right, .up]
    private static let names = ["DOWN / FRONT", "LEFT PROFILE", "RIGHT PROFILE", "UP / BACK"]
    private static let distances: [CGFloat] = [0, 12, 24, 36, 48, 60, 72, 84]
    private static let feet = CGPoint(x: 300, y: 40)

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }

    static func main() throws {
        _ = NSApplication.shared
        expect(PixelWalkingSprites.isAvailable, "the production four-direction atlas loads from bundled resources")
        var neutralHeadings = Set<UInt64>()
        for (index, direction) in directions.enumerated() {
            let neutral = frame(direction: direction, distance: 0, moving: false)
            neutralHeadings.insert(fingerprint(neutral))
            var frames = Set<UInt64>()
            var heights: [CGFloat] = []
            var baselines: [CGFloat] = []
            for distance in distances {
                let moving = frame(direction: direction, distance: distance, moving: true)
                frames.insert(fingerprint(moving))
                guard let bounds = inkBounds(moving) else { fatalError("Empty walking sprite") }
                heights.append(bounds.height)
                baselines.append(bounds.minY)
                expect(bounds.minX > 4 && bounds.maxX < 596 && bounds.minY > 4 && bounds.maxY < 396,
                       "\(names[index]) frame remains fully inside the canvas, including limbs and shoes")
            }
            expect(frames.count >= 2, "\(names[index]) changes authored stride frames while moving")
            expect(distances.allSatisfy {
                fingerprint(frame(direction: direction, distance: $0, moving: false)) == fingerprint(neutral)
            }, "\(names[index]) stops on a neutral frame during corner pauses and reduced motion")
            expect(heights.allSatisfy { (275...325).contains($0) },
                   "\(names[index]) keeps the worker's existing physical size")
            expect((heights.max()! - heights.min()!) <= 16,
                   "\(names[index]) does not resize the body between steps")
            expect(baselines.allSatisfy { (feet.y - 2...feet.y + 10).contains($0) }
                   && baselines.max()! - baselines.min()! <= 8,
                   "\(names[index]) keeps a planted shoe near the requested ground line")
            let invalid = [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity, -1, CGFloat.greatestFiniteMagnitude]
            expect(invalid.allSatisfy {
                inkBounds(frame(direction: direction, distance: $0, moving: true)) != nil
            }, "\(names[index]) safely handles invalid or very large travel distances")
            if direction == .down || direction == .up {
                let leads = stride(from: CGFloat(0), through: 100, by: 4).compactMap {
                    footLead(frame(direction: direction, distance: $0, moving: true))
                }
                expect(leads.contains { $0 >= 3 } && leads.contains { $0 <= -3 },
                       "\(names[index]) alternates the leading foot rather than hopping on the same leg")
            }
        }
        expect(neutralHeadings.count == 4, "front, left profile, right profile and rear are four distinct authored views")
        let contact = try writeContact()
        print("PASS: \(checks) production four-direction stride, pause, baseline, size and bounds checks; no window or user state touched")
        print("CONTACT: \(contact.path)")
    }

    private static func context(width: Int = 600, height: Int = 400) -> CGContext {
        let result = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        result.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return result
    }

    private static func frame(direction: PixelWalkDirection, distance: CGFloat, moving: Bool) -> CGContext {
        let canvas = context()
        guard PixelWalkingSprites.draw(in: canvas, direction: direction, distance: distance,
                                        isMoving: moving, feet: feet, pixelSize: 6) else {
            fatalError("Production walking sprite did not render")
        }
        return canvas
    }

    private static func fingerprint(_ context: CGContext) -> UInt64 {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 1469598103934665603
        for index in 0..<(context.width * context.height * 4) {
            hash = (hash ^ UInt64(bytes[index])) &* 1099511628211
        }
        return hash
    }

    private static func inkBounds(_ context: CGContext) -> CGRect? {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var left = context.width, right = -1, top = context.height, bottom = -1
        for row in 0..<context.height {
            for column in 0..<context.width where bytes[(row * context.width + column) * 4 + 3] >= 160 {
                left = min(left, column); right = max(right, column)
                top = min(top, row); bottom = max(bottom, row)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        return CGRect(x: left, y: context.height - 1 - bottom, width: right - left + 1, height: bottom - top + 1)
    }

    private static func footLead(_ context: CGContext) -> CGFloat? {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        // A forward shoe can cross the body's midline. Measure its contact
        // patch's centre, rather than assigning pixels to left/right halves.
        for y in Int(feet.y)..<Int(feet.y + 40) {
            var xTotal: CGFloat = 0, count: CGFloat = 0
            for contactY in y..<min(y + 4, context.height) {
                for x in Int(feet.x - 75)..<Int(feet.x + 75) {
                    if bytes[((context.height - 1 - contactY) * context.width + x) * 4 + 3] >= 160 {
                        xTotal += CGFloat(x); count += 1
                    }
                }
            }
            if count > 0 { return xTotal / count - feet.x }
        }
        return nil
    }

    private static func writeContact() throws -> URL {
        let canvas = context(width: 1600, height: 1440)
        canvas.setFillColor(NSColor(srgbRed: 0.73, green: 0.71, blue: 0.65, alpha: 1).cgColor)
        canvas.fill(CGRect(x: 0, y: 0, width: 1600, height: 1440))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
        for (row, direction) in directions.enumerated() {
            let ground = CGFloat(1440 - (row + 1) * 360 + 18)
            (names[row] as NSString).draw(at: CGPoint(x: 16, y: ground + 326),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
                                 .foregroundColor: NSColor(srgbRed: 0.18, green: 0.20, blue: 0.16, alpha: 1)])
            for (column, distance) in distances.enumerated() {
                _ = PixelWalkingSprites.draw(in: canvas, direction: direction, distance: distance,
                    isMoving: column != 0, feet: CGPoint(x: 100 + column * 200, y: Int(ground)), pixelSize: 6)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/walking")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("four-direction-contact.png")
        guard let image = canvas.makeImage(),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "WalkingSpriteTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "WalkingSpriteTests", code: 2) }
        return output
    }
}
