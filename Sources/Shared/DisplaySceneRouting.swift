import AppKit
import CoreGraphics

/// A screen's persistent identity is independent of the focused window and the
/// order in which macOS reports displays after hot plugging.
struct DisplaySceneDescriptor: Equatable {
    var id: String
    var name: String
    var frame: CGRect
    var isMain: Bool

    var positionTitle: String {
        isMain ? "主屏幕" : "外接屏幕"
    }
}

enum DisplaySceneRouting {
    static func mainScreen(screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first(where: { displayID(for: $0) == CGMainDisplayID() }) ?? screens.first
    }

    static func descriptors(screens: [NSScreen] = NSScreen.screens) -> [DisplaySceneDescriptor] {
        let mainID = CGMainDisplayID()
        let containsMain = screens.contains { displayID(for: $0) == mainID }
        return screens.enumerated().map { index, screen in
            let number = displayID(for: screen)
            return DisplaySceneDescriptor(id: identity(for: screen), name: screen.localizedName,
                frame: screen.frame, isMain: containsMain ? number == mainID : index == 0)
        }
    }

    static func identity(for screen: NSScreen) -> String {
        let display = displayID(for: screen)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
           let value = CFUUIDCreateString(nil, uuid) {
            return "display:\(value as String)"
        }
        // Only unusual virtual drivers omit the UUID. Avoid deriving identity
        // from screen position, which changes whenever displays are rearranged.
        return "display:\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(CGDisplaySerialNumber(display))-\(display)"
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func viewport(for screen: NSScreen?, world: SceneWorld = SceneWorld(),
                         context: SceneDisplayContext = .desktop) -> WorldViewport? {
        guard let screen else { return nil }
        let displays = descriptors()
        guard let display = displays.first(where: { $0.id == identity(for: screen) }) else { return nil }
        return viewport(for: display, among: displays, world: world, context: context)
    }

    static func viewport(for display: DisplaySceneDescriptor,
                         among displays: [DisplaySceneDescriptor], world: SceneWorld = SceneWorld(),
                         context: SceneDisplayContext = .desktop) -> WorldViewport? {
        WorldViewport.make(display: display.frame, among: displays.map(\.frame),
                           seams: seams(among: displays, world: world, context: context))
    }

    /// Only touching outdoor/room screens need a foreground connection. Every
    /// viewport receives the complete, sorted list, so both sides draw one edge.
    static func seams(among displays: [DisplaySceneDescriptor], world: SceneWorld,
                      context: SceneDisplayContext = .desktop) -> [WorldSeam] {
        var result: [WorldSeam] = []
        for first in displays.indices {
            for second in displays.indices where second > first {
                let a = displays[first], b = displays[second]
                let aKind = background(for: a, among: displays, world: world, context: context)
                let bKind = background(for: b, among: displays, world: world, context: context)
                guard aKind != bKind else { continue }
                let lower = max(a.frame.minY, b.frame.minY)
                let upper = min(a.frame.maxY, b.frame.maxY)
                guard upper > lower else { continue }
                let edge: WorldSeam
                if abs(a.frame.maxX - b.frame.minX) <= 1 {
                    edge = WorldSeam(boundaryX: (a.frame.maxX + b.frame.minX) / 2,
                                     lowerY: lower, upperY: upper, roomOnRight: bKind == .room)
                } else if abs(b.frame.maxX - a.frame.minX) <= 1 {
                    edge = WorldSeam(boundaryX: (b.frame.maxX + a.frame.minX) / 2,
                                     lowerY: lower, upperY: upper, roomOnRight: aKind == .room)
                } else { continue }
                if edge.isValid, !result.contains(edge) { result.append(edge) }
            }
        }
        return result.sorted {
            if $0.boundaryX != $1.boundaryX { return $0.boundaryX < $1.boundaryX }
            if $0.lowerY != $1.lowerY { return $0.lowerY < $1.lowerY }
            if $0.upperY != $1.upperY { return $0.upperY < $1.upperY }
            return !$0.roomOnRight && $1.roomOnRight
        }
    }

    static func background(for display: DisplaySceneDescriptor, among displays: [DisplaySceneDescriptor],
                           world: SceneWorld, context: SceneDisplayContext = .desktop) -> WorkplaceBackground {
        if let selected = world.displayScenes(for: context)[display.id] { return selected }
        // Desktop task boards start in every room. The system saver uses the
        // companion outdoor view by default; focus never changes either choice.
        if context == .desktop { return .room }
        return display.isMain || displays.count <= 1 ? .room : .outdoors
    }

    static func background(for screen: NSScreen?, world: SceneWorld,
                           context: SceneDisplayContext = .desktop) -> WorkplaceBackground {
        guard let screen else { return .room }
        let displays = descriptors()
        guard let display = displays.first(where: { $0.id == identity(for: screen) }) else { return .room }
        return background(for: display, among: displays, world: world, context: context)
    }

    static func screen(for window: NSWindow?) -> NSScreen? {
        guard let window else { return nil }
        if let screen = window.screen { return screen }
        // Saver hosts can temporarily omit window.screen while attaching their
        // remote view. Match the largest actual screen intersection in that case.
        return NSScreen.screens.compactMap { screen -> (NSScreen, CGFloat)? in
            let intersection = screen.frame.intersection(window.frame)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
            return (screen, intersection.width * intersection.height)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    static func layoutTitle(for display: DisplaySceneDescriptor, among displays: [DisplaySceneDescriptor]) -> String {
        if display.isMain { return "主屏幕" }
        guard let main = displays.first(where: \.isMain) else { return "外接屏幕" }
        if display.frame.midX < main.frame.minX { return "左侧屏幕" }
        if display.frame.midX > main.frame.maxX { return "右侧屏幕" }
        if display.frame.midY > main.frame.midY { return "上方屏幕" }
        if display.frame.midY < main.frame.midY { return "下方屏幕" }
        return "外接屏幕"
    }

    static func diagnostics(world: SceneWorld, context: SceneDisplayContext = .desktop) -> [[String: Any]] {
        let displays = descriptors()
        return displays.map { display in
            let camera = viewport(for: display, among: displays, world: world, context: context)
            return ["id": display.id, "name": display.name, "isMain": display.isMain,
             "position": layoutTitle(for: display, among: displays),
             "context": context.rawValue,
             "background": background(for: display, among: displays, world: world, context: context).rawValue,
             "hasExplicitChoice": world.displayScenes(for: context)[display.id] != nil,
             "worldCanvas": camera.map { [$0.canvas.minX, $0.canvas.minY, $0.canvas.width, $0.canvas.height] } ?? [],
             "worldSeams": camera?.seams.map { ["x": $0.boundaryX, "lowerY": $0.lowerY,
                                                  "upperY": $0.upperY, "roomOnRight": $0.roomOnRight] as [String: Any] } ?? [],
             "frame": [display.frame.minX, display.frame.minY, display.frame.width, display.frame.height]]
        }
    }
}
