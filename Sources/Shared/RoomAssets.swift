import AppKit
import ImageIO

private final class RoomResourceAnchor: NSObject {}

/// Artwork contains no clocks, progress values, task text or people.
/// Those are always separate live layers, including in the system saver host.
enum RoomAssets {
    private static let flatBackground = load("flat-cabin-background")
    /// Flat plates contain no fixed cat or sunbeams. Their matching dynamic
    /// layers must never be covered by patches from the older perspective art.
    static var usesFlatForeground: Bool { flatBackground != nil }
    static let background = flatBackground ?? load("cabin-background")
    static let outdoors = load("outdoor-landscape")
    static let panorama = usesFlatForeground
        ? load("flat-distant-panorama") ?? load("outdoor-panorama") : load("outdoor-panorama")
    static let gardenForeground = load("flat-garden-foreground")
    static let windowForeground = usesFlatForeground
        ? load("flat-room-window-cutout") : load("room-window-cutout")
    static let seamIvy = load("scene-edge-ivy")
    static let nightBackground = usesFlatForeground ? nil : load("cabin-background-night")
    private static let flatDesktop = load("flat-desk-top").flatMap(PixelAssetTransparency.cleaned)
    static let desktop = (usesFlatForeground
        ? flatDesktop ?? load("desk-top") : load("desk-top")).flatMap(trimTransparency)
    static let rugPatch = usesFlatForeground ? nil : load("rug-clean-patch")
    static var isAvailable: Bool { background != nil && desktop != nil }

    private static func load(_ name: String) -> CGImage? {
        let bundles = [Bundle(for: RoomResourceAnchor.self), Bundle.main]
        var urls = bundles.compactMap { $0.url(forResource: name, withExtension: "png", subdirectory: "Room") }
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Room/\(name).png"))
        guard let url = urls.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func trimTransparency(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h {
            for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 32 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        guard x1 >= x0 && y1 >= y0 else { return nil }
        return image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))
    }
}
