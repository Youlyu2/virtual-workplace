import CoreGraphics

/// Normalizes exported sprite alpha in the decoded cache only. The production
/// PNG remains untouched. Saturated matte keys are removed only when connected
/// to transparent space, never by a broad hue/chroma-key over the illustration.
enum PixelAssetTransparency {
    static func cleaned(_ source: CGImage) -> CGImage? {
        let width = source.width, height = source.height, count = width * height
        guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = c.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        c.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        // 0 = authored color, 1 = transparent export residue, 2 = strict matte.
        var kind = [UInt8](repeating: 0, count: count)
        var pending: [Int] = []
        for index in 0..<count {
            let i = index * 4, alpha = Int(pixels[i + 3])
            if alpha <= 8 {
                kind[index] = 1; pending.append(index)
            } else {
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let redKey = r * 100 > alpha * 94 && g * 100 < alpha * 5 && b * 100 < alpha * 5
                let greenKey = g * 100 > alpha * 94 && r * 100 < alpha * 5 && b * 100 < alpha * 5
                if redKey || greenKey {
                    kind[index] = 2
                    // The image edge also borders transparent space outside it.
                    if index < width || index >= count - width || index % width == 0 || index % width == width - 1 {
                        kind[index] = 1; pending.append(index)
                    }
                }
            }
        }
        var cursor = 0
        while cursor < pending.count {
            let index = pending[cursor]; cursor += 1
            let x = index % width, y = index / width
            for dy in -1...1 {
                let ny = y + dy
                guard ny >= 0, ny < height else { continue }
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    guard nx >= 0, nx < width else { continue }
                    let next = ny * width + nx
                    if kind[next] == 2 { kind[next] = 1; pending.append(next) }
                }
            }
        }
        for index in 0..<count {
            let i = index * 4
            if kind[index] == 1 {
                pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            } else if pixels[i + 3] >= 248 {
                // Flat authored surfaces should cover the old scenery fully.
                // Undo premultiplication when snapping near-opaque export alpha.
                let alpha = Int(pixels[i + 3])
                for channel in 0..<3 {
                    pixels[i + channel] = UInt8(min(255, (Int(pixels[i + channel]) * 255 + alpha / 2) / alpha))
                }
                pixels[i + 3] = 255
            }
        }
        return c.makeImage()
    }
}
