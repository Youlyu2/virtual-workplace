import AppKit

@main
struct SceneViewTests {
    private static var checks = 0
    private static func expect(_ result: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !result() { fatalError("FAIL: \(message)") }
    }

    static func main() {
        _ = NSApplication.shared
        let bounds = CGRect(x: 0, y: 0, width: 1672, height: 941)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = WorkplaceSceneView(frame: bounds)
        window.contentView = view
        expect(!window.isVisible, "regression host never displays or activates a window")
        expect(!view.isAnimating, "offscreen attached view does not start a continuous timer")

        view.snapshot = .empty()
        _ = capture(view)
        view.needsDisplay = false
        var active = SceneSnapshot.empty()
        active.mode = .sitting
        active.tasks = [WorkplaceTask(id: "static-monitor", title: "回归测试显示器", status: .running, slot: 0)]
        view.snapshot = active
        expect(view.needsDisplay, "new snapshot invalidates an attached view even with no visible occlusion flag")
        let actual = capture(view)
        expect(!view.isAnimating, "snapshot redraw does not restart the paused timer")
        let target = reference(active, bounds: bounds)
        assertTitleMatches(actual: actual, expected: target, bounds: bounds)

        view.isHidden = true
        view.needsDisplay = false
        view.snapshot = .empty()
        expect(!view.needsDisplay, "hidden view is not scheduled for redraw")
        view.isHidden = false
        expect(view.needsDisplay, "unhiding schedules the current complete frame")
        expect(!view.isAnimating, "unhiding an offscreen host does not start continuous animation")
        expect(!window.isVisible, "test leaves the window unshown")
        print("PASS: \(checks) static scene refresh checks; no window activation or user-state writes")
    }

    private static func capture(_ view: NSView) -> CGImage {
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage!
    }

    private static func reference(_ snapshot: SceneSnapshot, bounds: CGRect) -> CGImage {
        let ctx = context(width: Int(bounds.width), height: Int(bounds.height))
        SceneRenderer.draw(in: ctx, bounds: bounds, snapshot: snapshot, time: 0, reduceMotion: true)
        return ctx.makeImage()!
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Compare only real task-title pixels. Clocks and breathing sprites can
    /// change between draws, while this title must already be fully visible.
    private static func assertTitleMatches(actual: CGImage, expected: CGImage, bounds: CGRect) {
        let w = Int(bounds.width), h = Int(bounds.height)
        let a = context(width: w, height: h), e = context(width: w, height: h)
        a.interpolationQuality = .none; e.interpolationQuality = .none
        a.draw(actual, in: bounds); e.draw(expected, in: bounds)
        let ap = a.data!.assumingMemoryBound(to: UInt8.self)
        let ep = e.data!.assumingMemoryBound(to: UInt8.self)
        var bright = 0, matched = 0
        for y in 615..<649 {
            for x in 688..<946 {
                let i = ((h - 1 - y) * w + x) * 4
                guard ep[i] > 150, ep[i+1] > 170, ep[i+2] > 140 else { continue }
                bright += 1
                let delta = abs(Int(ap[i]) - Int(ep[i])) + abs(Int(ap[i+1]) - Int(ep[i+1])) + abs(Int(ap[i+2]) - Int(ep[i+2]))
                if delta < 105 { matched += 1 }
            }
        }
        expect(bright > 50, "reference title contains visible text pixels")
        expect(Double(matched) / Double(max(1, bright)) > 0.75,
               "single paused-view redraw renders the new task monitor fully opaque")
    }
}
