import AppKit

/// Each host owns its animation state. Rendering a preview never affects another display.
final class SceneAnimation {
    private var previousTime: TimeInterval?
    private var standing: CGFloat = 0
    private var slacking: CGFloat = 1
    private var opacity: [String: CGFloat] = [:]
    private var leaving: [String: WorkplaceTask] = [:]

    func reset() { previousTime = nil }

    func frame(snapshot: SceneSnapshot, time: TimeInterval, reduceMotion: Bool, now: Date = Date()) -> SceneFrame {
        let pose = snapshot.resolvedPose(at: now)
        let targetStand: CGFloat = pose == .standing ? 1 : 0
        let targetSlack: CGFloat = pose == .slacking ? 1 : 0
        let first = previousTime == nil
        let delta = min(0.1, max(0, time - (previousTime ?? time)))
        previousTime = time
        let weight: CGFloat = first || reduceMotion ? 1 : CGFloat(1 - exp(-delta * 9))
        standing += (targetStand - standing) * weight
        slacking += (targetSlack - slacking) * weight
        let currentIDs = Set(snapshot.tasks.map(\.id))
        for task in snapshot.tasks { leaving[task.id] = task }
        for id in Array(leaving.keys) {
            let target: CGFloat = currentIDs.contains(id) ? 1 : 0
            let previous = opacity[id] ?? (first ? target : 0)
            let value = previous + (target - previous) * weight
            opacity[id] = value
            if target == 0 && value < 0.01 { opacity.removeValue(forKey: id); leaving.removeValue(forKey: id) }
        }
        return SceneFrame(standing: standing, slacking: slacking,
                          screens: leaving.values.sorted { $0.slot < $1.slot }.map { ($0, opacity[$0.id] ?? 1) })
    }
}

struct SceneFrame {
    var standing: CGFloat
    var slacking: CGFloat
    var screens: [(WorkplaceTask, CGFloat)]
}

/// Both the app and the system screen saver use the same rear-view composition.
enum SceneRenderer {
    static var hasRoomAssets: Bool { RoomAssets.isAvailable && PixelEmployee.hasSprites }
    static var hasOutdoorAssets: Bool { OutdoorWorkplaceScene.isAvailable }

    /// The window opening keeps the physical display's camera even in a small
    /// control preview. Letterboxing the room never stretches that world view.
    static func roomWorldBounds(for viewport: WorldViewport) -> CGRect {
        let display = viewport.display.size
        let fillsDisplay = (1.50...1.90).contains(display.width / display.height)
        let scale = fillsDisplay ? max(display.width / 1672, display.height / 941)
            : min(display.width / 1672, display.height / 941)
        return CGRect(x: 836 - display.width / (2 * scale), y: 470.5 - display.height / (2 * scale),
                      width: display.width / scale, height: display.height / scale)
    }
    static func draw(in c: CGContext, bounds: CGRect, snapshot sourceSnapshot: SceneSnapshot, time: TimeInterval,
                     reduceMotion: Bool, animation: SceneAnimation? = nil, now: Date = Date(),
                     background: WorkplaceBackground = .room, viewport: WorldViewport? = nil) {
        // Resolve the same absolute-time policy in every host. Keep the saved
        // manual weather untouched while the shared random calendar advances.
        var snapshot = sourceSnapshot
        snapshot.world = sourceSnapshot.effectiveWorld(at: now)
        c.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        let worldViewport = viewport ?? WorldViewport.companion(for: background)
        if background == .outdoors {
            OutdoorWorkplaceScene.draw(in: c, bounds: bounds, world: snapshot.world ?? SceneWorld(),
                                       at: now, reduceMotion: reduceMotion, viewport: worldViewport)
            PendingNoteVisitors.draw(in: c, bounds: bounds, notes: snapshot.pendingNotes ?? [],
                                     world: snapshot.world ?? SceneWorld(), at: now, reduceMotion: reduceMotion)
            NSGraphicsContext.restoreGraphicsState()
            c.restoreGState()
            return
        }
        c.setFillColor(NSColor(srgbRed: 0.22, green: 0.14, blue: 0.09, alpha: 1).cgColor)
        c.fill(bounds)
        // Keep characters square and every information layer visible on 16:10,
        // ultrawide and portrait displays. A quiet pixel wood frame fills gutters.
        for row in stride(from: Int(bounds.minY), to: Int(bounds.maxY) + 24, by: 24) {
            let even = (row / 24) % 2 == 0
            c.setFillColor(NSColor(srgbRed: even ? 0.25 : 0.27, green: even ? 0.16 : 0.17, blue: 0.10, alpha: 1).cgColor)
            c.fill(CGRect(x: bounds.minX, y: CGFloat(row), width: bounds.width, height: 23))
        }
        let aspect = bounds.width / max(1, bounds.height)
        // Common Mac and 16:9 monitors use the entire screen. Only outer decor
        // is cropped; clocks and the sleeping sprite adapt to the visible edge.
        let fillsDisplay = (1.50...1.90).contains(aspect)
        let scale = fillsDisplay ? max(bounds.width / 1672, bounds.height / 941)
            : min(bounds.width / 1672, bounds.height / 941)
        let visibleRect = fillsDisplay ? CGRect(x: 836 - bounds.width / (2 * scale),
            y: 470.5 - bounds.height / (2 * scale), width: bounds.width / scale, height: bounds.height / scale)
            : CGRect(origin: .zero, size: FullscreenWorkplaceScene.size)
        c.translateBy(x: bounds.midX - 836 * scale, y: bounds.midY - 470.5 * scale)
        c.scaleBy(x: scale, y: scale)
        c.setAllowsAntialiasing(true)
        var frame = animation?.frame(snapshot: snapshot, time: time, reduceMotion: reduceMotion, now: now)
            ?? SceneFrame(standing: snapshot.resolvedPose(at: now) == .standing ? 1 : 0,
                          slacking: snapshot.resolvedPose(at: now) == .slacking ? 1 : 0,
                          screens: snapshot.tasks.sorted { $0.slot < $1.slot }.map { ($0, 1) })
        let action = snapshot.action.flatMap { $0.isActive(at: now) ? $0 : nil }
        let progress = action.map { CGFloat($0.progress(at: now)) }
        var actionBlend: CGFloat = 0
        if let action {
            let elapsed = now.timeIntervalSince(action.startedAt)
            func smooth(_ x: Double) -> CGFloat {
                let value = max(0, min(1, x))
                return CGFloat(value * value * (3 - 2 * value))
            }
            let fade: Double = action.kind == .walk || action.kind == .playWithCat ? 0.22 : 0.5
            actionBlend = reduceMotion ? 1 : min(smooth(elapsed / fade), smooth((action.kind.duration - elapsed) / fade))
            if action.kind != .playWithCat && action.kind != .walk { frame.standing += (1 - frame.standing) * actionBlend }
            frame.slacking *= 1 - actionBlend
        }
        FullscreenWorkplaceScene.draw(in: c, snapshot: snapshot, frame: frame, time: reduceMotion ? 0 : time,
                                      visibleRect: visibleRect, actionProgress: progress,
                                      actionBlend: actionBlend, reduceMotion: reduceMotion, now: now,
                                      viewport: worldViewport, worldBounds: roomWorldBounds(for: worldViewport))
        NSGraphicsContext.restoreGraphicsState()
        c.restoreGState()
    }
}
