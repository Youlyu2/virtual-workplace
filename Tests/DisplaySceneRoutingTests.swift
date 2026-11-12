import AppKit

@main
enum DisplaySceneRoutingTests {
    private static var checks = 0
    private static func expect(_ result: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !result() { fatalError("FAIL: \(message)") }
    }
    static func main() {
        let main = DisplaySceneDescriptor(id: "main-uuid", name: "Display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        let left = DisplaySceneDescriptor(id: "left-uuid", name: "Display", frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440), isMain: false)
        let displays = [main, left]
        var world = SceneWorld()
        let mainViewport = DisplaySceneRouting.viewport(for: main, among: displays, context: .screenSaver)
        let leftViewport = DisplaySceneRouting.viewport(for: left, among: displays, context: .screenSaver)
        expect(mainViewport?.canvas == CGRect(x: -2560, y: 0, width: 4480, height: 1440),
            "routing builds one canvas from the actual monitor union")
        expect(mainViewport?.canvas == leftViewport?.canvas && mainViewport?.display == main.frame
               && leftViewport?.display == left.frame,
            "each screen receives its own physical crop of the shared world")
        let defaultSeam = WorldSeam(boundaryX: 0, lowerY: 0, upperY: 1080, roomOnRight: true)
        expect(mainViewport?.seams == [defaultSeam] && leftViewport?.seams == [defaultSeam],
            "saver room and outdoor viewports share a foreground edge over their actual height overlap")
        let desktopMain = DisplaySceneRouting.viewport(for: main, among: displays)
        let desktopLeft = DisplaySceneRouting.viewport(for: left, among: displays)
        expect(DisplaySceneRouting.background(for: main, among: displays, world: world) == .room
               && DisplaySceneRouting.background(for: left, among: displays, world: world) == .room,
            "default desktop context shows the task room on both monitors")
        expect(desktopMain?.seams.isEmpty == true && desktopLeft?.seams.isEmpty == true,
            "the desktop room pair has no outdoor foreground seam")
        expect(desktopMain?.canvas == mainViewport?.canvas && desktopLeft?.display == leftViewport?.display,
            "desktop and saver share physical camera geometry while selecting independent decorations")
        expect(DisplaySceneRouting.background(for: Optional<NSScreen>.none, world: world, context: .screenSaver) == .room,
            "an unattached saver host has a safe room background")
        expect(DisplaySceneRouting.viewport(for: left, among: [left, main], context: .screenSaver) == leftViewport,
            "inventory ordering cannot change a display's viewport")
        expect(DisplaySceneRouting.viewport(for: Optional<NSScreen>.none) == nil,
            "an unattached host can select its explicit companion fallback")
        expect(DisplaySceneRouting.background(for: main, among: displays, world: world, context: .screenSaver) == .room,
            "the actual main screen starts in the room")
        expect(DisplaySceneRouting.background(for: left, among: displays, world: world, context: .screenSaver) == .outdoors,
            "the additional left screen starts outside")
        expect(DisplaySceneRouting.layoutTitle(for: left, among: displays) == "左侧屏幕",
            "a negative-coordinate screen is identified as left")
        expect(DisplaySceneRouting.background(for: main, among: [left, main], world: world, context: .screenSaver) == .room,
            "screen inventory order cannot move the room to another monitor")
        expect(DisplaySceneRouting.background(for: left, among: [left, main], world: world, context: .screenSaver) == .outdoors,
            "screen inventory order cannot move the outdoor view")
        expect(DisplaySceneRouting.background(for: main, among: [main], world: world, context: .screenSaver) == .room,
            "a single main monitor keeps the room")
        expect(DisplaySceneRouting.background(for: left, among: [left], world: world, context: .screenSaver) == .room,
            "a single external monitor also has a usable room fallback")

        world.screenSaverDisplayScenes[main.id] = .outdoors
        world.screenSaverDisplayScenes[left.id] = .room
        let reverseSeam = WorldSeam(boundaryX: 0, lowerY: 0, upperY: 1080, roomOnRight: false)
        expect(DisplaySceneRouting.viewport(for: main, among: displays, world: world, context: .screenSaver)?.seams == [reverseSeam]
               && DisplaySceneRouting.viewport(for: left, among: displays, world: world, context: .screenSaver)?.seams == [reverseSeam],
            "explicit scene swaps mirror the edge without moving its world position")
        expect(DisplaySceneRouting.background(for: main, among: displays, world: world, context: .screenSaver) == .outdoors,
            "the main screen accepts an explicit outdoor choice")
        expect(DisplaySceneRouting.background(for: left, among: displays, world: world, context: .screenSaver) == .room,
            "the left screen accepts an explicit room choice")
        expect(DisplaySceneRouting.background(for: left, among: [left], world: world, context: .screenSaver) == .room,
            "disconnecting the other screen preserves the external's explicit choice")
        var movedLeft = left
        movedLeft.frame.origin.x = 1920
        expect(DisplaySceneRouting.background(for: movedLeft, among: [main, movedLeft], world: world, context: .screenSaver) == .room,
            "rearranging a monitor keeps the choice attached to its persistent ID")
        expect(DisplaySceneRouting.layoutTitle(for: movedLeft, among: [main, movedLeft]) == "右侧屏幕",
            "rearrangement updates only the position label")
        expect(main.name == left.name && world.screenSaverDisplayScenes[main.id] != world.screenSaverDisplayScenes[left.id],
            "identical human-readable monitor names remain independently configurable")

        let before = world
        let newLeft = DisplaySceneDescriptor(id: "new-uuid", name: "New monitor", frame: left.frame, isMain: false)
        expect(DisplaySceneRouting.background(for: newLeft, among: [main, newLeft], world: world, context: .screenSaver) == .outdoors,
            "a newly connected monitor receives a recommended scene")
        expect(world == before && world.screenSaverDisplayScenes[left.id] == .room,
            "routing a hot-plugged monitor cannot delete a disconnected monitor's saved choice")
        let above = DisplaySceneDescriptor(id: "above", name: "Above", frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), isMain: false)
        let below = DisplaySceneDescriptor(id: "below", name: "Below", frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), isMain: false)
        expect(DisplaySceneRouting.layoutTitle(for: above, among: [main, above]) == "上方屏幕",
            "stacked displays have an unambiguous upper label")
        expect(DisplaySceneRouting.layoutTitle(for: below, among: [main, below]) == "下方屏幕",
            "stacked displays have an unambiguous lower label")
        world.screenSaverDisplayScenes.removeAll()
        let mainOnLeft = DisplaySceneDescriptor(id: main.id, name: main.name, frame: left.frame, isMain: true)
        let secondOnRight = DisplaySceneDescriptor(id: left.id, name: left.name, frame: main.frame, isMain: false)
        expect(DisplaySceneRouting.background(for: mainOnLeft, among: [mainOnLeft, secondOnRight], world: world, context: .screenSaver) == .room,
            "the main-screen role takes priority when the main display is physically leftmost")
        expect(DisplaySceneRouting.background(for: secondOnRight, among: [mainOnLeft, secondOnRight], world: world, context: .screenSaver) == .outdoors,
            "the other monitor still defaults outside when the main screen is on the left")

        let allRooms = SceneWorld(screenSaverDisplayScenes: [main.id: .room, left.id: .room])
        let allOutdoors = SceneWorld(screenSaverDisplayScenes: [main.id: .outdoors, left.id: .outdoors])
        expect(DisplaySceneRouting.seams(among: displays, world: allRooms, context: .screenSaver).isEmpty,
            "two room backgrounds do not acquire an exterior foreground edge")
        expect(DisplaySceneRouting.viewport(for: main, among: displays, world: allOutdoors, context: .screenSaver)?.seams.isEmpty == true,
            "two outdoor backgrounds keep their unobstructed panoramic connection")
        var separated = left
        separated.frame.origin.x -= 4
        expect(DisplaySceneRouting.seams(among: [main, separated], world: SceneWorld(), context: .screenSaver).isEmpty,
            "screens with a physical gap do not receive a false connecting edge")
        var nearTouching = left
        nearTouching.frame.origin.x -= 1
        expect(DisplaySceneRouting.seams(among: [main, nearTouching], world: SceneWorld(), context: .screenSaver).first?.boundaryX == -0.5,
            "one-point layout rounding uses the middle of the touching screen edges")
        expect(DisplaySceneRouting.seams(among: [main, above], world: SceneWorld(), context: .screenSaver).isEmpty,
            "stacked screens do not receive a vertical room boundary")
        let corner = DisplaySceneDescriptor(id: "corner", name: "Corner", frame: CGRect(x: 1920, y: 1080,
            width: 1920, height: 1080), isMain: false)
        expect(DisplaySceneRouting.seams(among: [main, corner], world: SceneWorld(), context: .screenSaver).isEmpty,
            "screens touching at a point have no positive-height foreground edge")
        var raised = left
        raised.frame.origin.y = 180
        expect(DisplaySceneRouting.seams(among: [main, raised], world: SceneWorld(), context: .screenSaver)
               == [WorldSeam(boundaryX: 0, lowerY: 180, upperY: 1080, roomOnRight: true)],
            "a vertically shifted neighbor decorates only the shared height")
        let right = DisplaySceneDescriptor(id: "right", name: "Right", frame: CGRect(x: 1920, y: 0,
            width: 1920, height: 1080), isMain: false)
        let triple = [right, main, left]
        let expectedSeams = [defaultSeam, WorldSeam(boundaryX: 1920, lowerY: 0, upperY: 1080, roomOnRight: false)]
        expect(DisplaySceneRouting.seams(among: triple, world: SceneWorld(), context: .screenSaver) == expectedSeams,
            "a room between two outdoor monitors has two deterministically ordered edges")
        expect(triple.allSatisfy {
            DisplaySceneRouting.viewport(for: $0, among: triple, world: SceneWorld(), context: .screenSaver)?.seams == expectedSeams
        }, "every monitor carries the same complete edge list")
        expect(DisplaySceneRouting.seams(among: [main, left, left], world: SceneWorld(), context: .screenSaver) == [defaultSeam],
            "mirrored duplicate display frames cannot double the foreground decoration")

        var independent = SceneWorld(weather: .rain, timeMode: .night,
            displayScenes: [main.id: .outdoors, left.id: .room],
            screenSaverDisplayScenes: [main.id: .room, left.id: .outdoors])
        expect(DisplaySceneRouting.background(for: main, among: displays, world: independent) == .outdoors
               && DisplaySceneRouting.background(for: main, among: displays, world: independent, context: .screenSaver) == .room,
            "one physical display can have a separate desktop and saver selection")
        expect(DisplaySceneRouting.viewport(for: main, among: displays, world: independent)?.seams == [reverseSeam]
               && DisplaySceneRouting.viewport(for: main, among: displays, world: independent, context: .screenSaver)?.seams == [defaultSeam],
            "viewport foreground edges resolve only the requested context")
        let beforeSaver = independent.screenSaverDisplayScenes
        independent.setDisplayScenes([main.id: .room, left.id: .room], for: .desktop)
        expect(independent.screenSaverDisplayScenes == beforeSaver
               && DisplaySceneRouting.seams(among: displays, world: independent).isEmpty
               && DisplaySceneRouting.seams(among: displays, world: independent, context: .screenSaver) == [defaultSeam],
            "editing desktop backgrounds leaves the saver layout and connection intact")
        independent.setDisplayScenes([main.id: .outdoors, left.id: .outdoors], for: .screenSaver)
        expect(independent.displayScenes == [main.id: .room, left.id: .room]
               && DisplaySceneRouting.seams(among: displays, world: independent, context: .screenSaver).isEmpty
               && independent.weather == .rain && independent.timeMode == .night,
            "editing saver backgrounds preserves desktop task rooms and shared weather and time")
        let legacyDesktop = SceneWorld(displayScenes: [main.id: .room, left.id: .room])
        expect(DisplaySceneRouting.seams(among: displays, world: legacyDesktop).isEmpty
               && DisplaySceneRouting.seams(among: displays, world: legacyDesktop, context: .screenSaver) == [defaultSeam],
            "legacy desktop choices do not suppress the recommended saver outdoor view")
        let onlyDesktopOverride = SceneWorld(displayScenes: [left.id: .outdoors])
        expect(DisplaySceneRouting.background(for: left, among: [left], world: onlyDesktopOverride) == .outdoors
               && DisplaySceneRouting.background(for: left, among: [left], world: onlyDesktopOverride, context: .screenSaver) == .room,
            "one-context explicit choices do not leak across contexts on a single monitor")
        let ocean = SceneWorld(theme: .underwater)
        let oceanDesktop = triple.compactMap { DisplaySceneRouting.viewport(for: $0, among: triple, world: ocean) }
        expect(Set(oceanDesktop.map(\.animationOffset)) == [0, 37, 74],
            "three monitors showing the same shallow reef use distinct animation phases")
        let oceanSaver = triple.compactMap {
            DisplaySceneRouting.viewport(for: $0, among: triple, world: ocean, context: .screenSaver)
        }
        expect(oceanSaver.map(\.animationOffset) == [37, 0, 0],
            "only the repeated deep scene receives an offset in the saver layout")
        expect(DisplaySceneRouting.viewport(for: right, among: [left, right, main], world: ocean) == oceanDesktop[0],
            "monitor inventory order cannot shift the animation timeline")
        expect(DisplaySceneRouting.viewport(for: main, among: [main], world: ocean)?.animationOffset == 0,
            "a single display uses the original animation timeline")
        print("PASS: \(checks) display scene routing checks (synthetic monitors only)")
    }
}
