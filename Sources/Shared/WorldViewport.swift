import Foundation
import CoreGraphics

/// A decorative room/outdoor boundary in the same global display coordinates
/// as the panorama. It describes foreground placement, never a camera offset.
struct WorldSeam: Equatable {
    let boundaryX: CGFloat
    let lowerY: CGFloat
    let upperY: CGFloat
    let roomOnRight: Bool

    var isValid: Bool {
        boundaryX.isFinite && lowerY.isFinite && upperY.isFinite && upperY > lowerY
            && (upperY - lowerY).isFinite
    }
}

/// A physical screen is a crop of one world-sized canvas. Coordinates are
/// macOS global display points (bottom-left origin), never window-local pixels.
struct WorldViewport: Equatable {
    let canvas: CGRect
    let display: CGRect
    let seams: [WorldSeam]
    let animationOffset: TimeInterval

    init?(canvas: CGRect, display: CGRect, seams: [WorldSeam] = [], animationOffset: TimeInterval = 0) {
        guard Self.valid(canvas), Self.valid(display), animationOffset.isFinite,
              canvas.insetBy(dx: -0.001, dy: -0.001).contains(display),
              seams.count <= 128, seams.allSatisfy({ seam in
                  seam.isValid && seam.boundaryX >= canvas.minX - 0.001
                    && seam.boundaryX <= canvas.maxX + 0.001
                    && seam.lowerY >= canvas.minY - 0.001 && seam.upperY <= canvas.maxY + 0.001
              }) else { return nil }
        self.canvas = canvas
        self.display = display
        self.seams = seams
        self.animationOffset = animationOffset
    }

    static func make(display: CGRect, among displays: [CGRect], seams: [WorldSeam] = [],
                     animationOffset: TimeInterval = 0) -> WorldViewport? {
        guard !displays.isEmpty, displays.allSatisfy(valid), valid(display),
              displays.contains(display) else { return nil }
        let canvas = displays.dropFirst().reduce(displays[0]) { $0.union($1) }
        return WorldViewport(canvas: canvas, display: display, seams: seams, animationOffset: animationOffset)
    }

    /// Offscreen exports have no physical target. Keep a deterministic pair so
    /// their left outdoor / right room cameras are still companion views.
    static func companion(for background: WorkplaceBackground) -> WorldViewport {
        let room = CGRect(x: 0, y: 0, width: 1672, height: 941)
        let outdoors = room.offsetBy(dx: -room.width, dy: 0)
        return WorldViewport(canvas: room.union(outdoors),
                             display: background == .outdoors ? outdoors : room,
                             seams: [WorldSeam(boundaryX: 0, lowerY: 0, upperY: 941, roomOnRight: true)])!
    }

    /// Drawing bounds are supplied by the renderer and have the same logical
    /// orientation as the display. Both axes preserve their shared global origin.
    func mapping(into bounds: CGRect) -> CGAffineTransform {
        let sx = bounds.width / display.width
        let sy = bounds.height / display.height
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
            tx: bounds.minX - display.minX * sx,
            ty: bounds.minY - display.minY * sy)
    }

    func worldPoint(_ point: CGPoint, into bounds: CGRect) -> CGPoint {
        point.applying(mapping(into: bounds))
    }

    func worldRect(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        rect.applying(mapping(into: bounds))
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
            && rect.minX.isFinite && rect.maxX.isFinite
            && rect.minY.isFinite && rect.maxY.isFinite
    }
}
