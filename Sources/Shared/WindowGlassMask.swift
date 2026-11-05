import Foundation
import CoreGraphics

/// The generated cutout supplies alpha only. The approved room colors remain
/// untouched, and the authored panes are always the outer safety boundary.
enum WindowGlassMask {
    static let bounds = RoomAssets.usesFlatForeground
        ? CGRect(x: 94, y: 538, width: 300, height: 226)
        : CGRect(x: 42, y: 553, width: 278, height: 356)
    private static let canvas = CGRect(x: 0, y: 0, width: 1672, height: 941)
    static let path: CGPath = {
        let result = CGMutablePath()
        if RoomAssets.usesFlatForeground {
            // The new window is a frontal 3×3 grid. Plants and the curtain
            // within these rectangles are protected by the foreground alpha.
            for (x, width): (CGFloat, CGFloat) in [(94, 88), (199, 92), (306, 88)] {
                for (y, height): (CGFloat, CGFloat) in [(539, 63), (617, 67), (699, 65)] {
                    result.addRect(CGRect(x: x, y: y, width: width, height: height))
                }
            }
            return result
        }
        let panes: [[CGPoint]] = [
            [CGPoint(x: 54,y: 901),CGPoint(x:111,y:890),CGPoint(x:111,y:789),CGPoint(x:48,y:796)],
            [CGPoint(x:151,y:882),CGPoint(x:235,y:870),CGPoint(x:235,y:778),CGPoint(x:151,y:786)],
            [CGPoint(x:249,y:865),CGPoint(x:315,y:855),CGPoint(x:315,y:773),CGPoint(x:249,y:779)],
            [CGPoint(x:48,y:776),CGPoint(x:111,y:768),CGPoint(x:111,y:691),CGPoint(x:46,y:694)],
            [CGPoint(x:151,y:769),CGPoint(x:235,y:761),CGPoint(x:235,y:692),CGPoint(x:151,y:693)],
            [CGPoint(x:249,y:760),CGPoint(x:315,y:753),CGPoint(x:315,y:691),CGPoint(x:249,y:691)],
            [CGPoint(x:46,y:677),CGPoint(x:111,y:676),CGPoint(x:111,y:566),CGPoint(x:43,y:554)],
            [CGPoint(x:151,y:676),CGPoint(x:235,y:677),CGPoint(x:235,y:581),CGPoint(x:151,y:560)],
            [CGPoint(x:249,y:676),CGPoint(x:315,y:677),CGPoint(x:315,y:595),CGPoint(x:249,y:580)]
        ]
        for points in panes { result.addLines(between: points); result.closeSubpath() }
        return result
    }()

    private static let cachedMask = makeMask(foreground: RoomAssets.windowForeground)
    static var usesArtworkMask: Bool { cachedMask != nil }

    static func clip(in context: CGContext) { clip(in: context, using: cachedMask) }

    /// Intersecting with the geometric panes prevents a misplaced transparent
    /// pixel elsewhere in the asset from erasing any part of the room.
    static func clip(in context: CGContext, using mask: CGImage?) {
        context.addPath(path)
        context.clip()
        if let mask { context.clip(to: bounds, mask: mask) }
        else if RoomAssets.usesFlatForeground {
            // Missing alpha must not paint weather over the curtain/flowers.
            // Restrict the fallback to known unobstructed parts of the panes.
            let safe = CGMutablePath()
            for rect in [CGRect(x:147,y:701,width:34,height:60),
                         CGRect(x:200,y:701,width:89,height:60),
                         CGRect(x:308,y:701,width:83,height:60),
                         CGRect(x:120,y:619,width:61,height:63),
                         CGRect(x:200,y:619,width:89,height:63),
                         CGRect(x:308,y:619,width:83,height:63),
                         CGRect(x:200,y:541,width:54,height:59)] {
                safe.addRect(rect)
            }
            context.addPath(safe); context.clip()
        }
    }

    /// A compact, cached RGBA image whose alpha permits only confidently empty
    /// glass pixels. RGB from the generated foreground is never used.
    static func makeMask(foreground: CGImage?) -> CGImage? {
        let width = Int(canvas.width), height = Int(canvas.height)
        // Image-generation exports may differ by a pixel while retaining the
        // same composition. Normalize alpha exactly as the room plate is drawn.
        guard let foreground, foreground.width >= width / 2, foreground.height >= height / 2,
              abs(CGFloat(foreground.width) / CGFloat(foreground.height) - canvas.width / canvas.height) < 0.01,
              let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.interpolationQuality = .none
        context.draw(foreground, in: canvas)
        // Reject unrelated all-transparent assets and partially exported room
        // plates. The full-room foreground must remain opaque outside glass.
        var exteriorSamples = 0, exteriorTransparent = 0
        for row in stride(from: 0, to: height, by: 16) {
            for column in stride(from: 0, to: width, by: 16) {
                let point = CGPoint(x: CGFloat(column) + 0.5, y: CGFloat(height - row) - 0.5)
                guard !bounds.contains(point) else { continue }
                exteriorSamples += 1
                if pixels[(row * width + column) * 4 + 3] < 240 { exteriorTransparent += 1 }
            }
        }
        guard exteriorSamples > 0, Double(exteriorTransparent) / Double(exteriorSamples) <= 0.005 else { return nil }

        let maskWidth = Int(bounds.width), maskHeight = Int(bounds.height)
        let sourceX = Int(bounds.minX), sourceRow = height - Int(bounds.maxY)
        var panePixels = 0, emptyPixels = 0
        var permitted = [Bool](repeating: false, count: maskWidth * maskHeight)
        for row in 0..<maskHeight {
            for column in 0..<maskWidth {
                let point = CGPoint(x: bounds.minX + CGFloat(column) + 0.5,
                                    y: bounds.maxY - CGFloat(row) - 0.5)
                guard path.contains(point) else { continue }
                panePixels += 1
                let offset = ((sourceRow + row) * width + sourceX + column) * 4 + 3
                // Semi-transparent antialiasing belongs to the foreground.
                // Eroding the empty area one pixel keeps leaf and frame edges.
                guard pixels[offset] <= 24 else { continue }
                emptyPixels += 1
                var clear = true
                for dy in -1...1 {
                    for dx in -1...1 {
                        let x = sourceX + column + dx, y = sourceRow + row + dy
                        if x < 0 || x >= width || y < 0 || y >= height
                            || pixels[(y * width + x) * 4 + 3] > 24 { clear = false }
                    }
                }
                permitted[row * maskWidth + column] = clear
            }
        }
        // An opaque or near-opaque foreground is not a usable glass cutout.
        guard panePixels > 0, Double(emptyPixels) / Double(panePixels) >= 0.03,
              permitted.contains(true) else { return nil }
        var rgba = [UInt8](repeating: 0, count: maskWidth * maskHeight * 4)
        for index in permitted.indices where permitted[index] {
            let offset = index * 4
            rgba[offset] = 255; rgba[offset + 1] = 255; rgba[offset + 2] = 255; rgba[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: maskWidth, height: maskHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: maskWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
