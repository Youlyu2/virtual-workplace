import Foundation
import CoreGraphics

@main enum WorldViewportTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), "FAIL: \(message)")
    }
    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    static func main() throws {
        let room = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let left = room.offsetBy(dx: -room.width, dy: 0)
        let mainCamera = WorldViewport.make(display: room, among: [room, left])!
        let leftCamera = WorldViewport.make(display: left, among: [room, left])!
        expect(mainCamera.canvas == CGRect(x: -1920, y: 0, width: 3840, height: 1080),
               "negative-origin displays create a single global canvas")
        expect(mainCamera.canvas == leftCamera.canvas && mainCamera.display == room && leftCamera.display == left,
               "both displays crop the same world, with distinct physical targets")
        expect(WorldViewport.make(display: room, among: [left, room]) == mainCamera,
               "screen discovery order cannot change the camera")
        let local = CGRect(x: 0, y: 0, width: 1672, height: 941)
        let seam = CGPoint(x: 0, y: 731)
        let rightEdge = leftCamera.worldPoint(seam, into: local)
        let leftEdge = mainCamera.worldPoint(seam, into: local)
        expect(near(rightEdge.x, local.maxX) && near(leftEdge.x, local.minX),
               "a physical seam maps to the touching edge of each rendered view")
        expect(near(rightEdge.y, leftEdge.y), "the same world horizon has equal height on neighboring screens")
        let preceding = leftCamera.worldPoint(CGPoint(x: -1, y: 731), into: local)
        let following = mainCamera.worldPoint(CGPoint(x: 1, y: 731), into: local)
        expect(near(local.maxX - preceding.x, following.x),
               "one global point next to the seam has the same logical pixel distance on either display")

        let raised = CGRect(x: -2560, y: 180, width: 2560, height: 1440)
        let raisedCamera = WorldViewport.make(display: raised, among: [room, raised])!
        expect(raisedCamera.canvas == CGRect(x: -2560, y: 0, width: 4480, height: 1620),
               "different display dimensions and vertical offsets retain their physical placement")
        let physicalBounds = CGRect(origin: .zero, size: raised.size)
        let physicalPoint = raisedCamera.worldPoint(CGPoint(x: -100, y: 880), into: physicalBounds)
        expect(physicalPoint == CGPoint(x: 2460, y: 700), "physical offsets are subtracted before local scaling")
        let worldMarker = CGRect(x: -1280, y: 900, width: 80, height: 40)
        let mappedMarker = raisedCamera.worldRect(worldMarker, into: CGRect(x: 10, y: 20, width: 1280, height: 720))
        expect(mappedMarker == CGRect(x: 650, y: 380, width: 40, height: 20),
               "world rectangles retain a consistent scale and destination origin")
        let upper = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        expect(WorldViewport.make(display: upper, among: [room, upper])?.canvas
               == CGRect(x: 0, y: 0, width: 1920, height: 2160), "vertically stacked monitors use the full union")
        let gap = room.offsetBy(dx: -2020, dy: 0)
        expect(WorldViewport.make(display: gap, among: [gap, room])?.canvas.width == 3940,
               "a physical gap is retained instead of closing the two scene cameras together")
        expect(WorldViewport.make(display: room, among: [room])?.canvas == room,
               "a single screen has a valid one-screen canvas")
        expect(WorldViewport.make(display: room, among: [room, room])?.canvas == room,
               "mirrored identical screen frames do not double the world width")

        let companionRoom = WorldViewport.companion(for: .room)
        let companionOutside = WorldViewport.companion(for: .outdoors)
        expect(companionRoom.canvas == CGRect(x: -1672, y: 0, width: 3344, height: 941),
               "offline exports have a deterministic paired world")
        expect(companionRoom.canvas == companionOutside.canvas
               && companionRoom.display.minX == 0 && companionOutside.display.maxX == 0,
               "offline room and landscape views meet at the same virtual seam")
        expect(companionRoom.seams == companionOutside.seams
               && companionRoom.seams == [WorldSeam(boundaryX: 0, lowerY: 0, upperY: 941, roomOnRight: true)],
               "companion views share one foreground edge with the room on its right")
        let decoration = WorldSeam(boundaryX: 0, lowerY: 0, upperY: 1080, roomOnRight: true)
        let decoratedCamera = WorldViewport.make(display: room, among: [room, left], seams: [decoration])!
        expect(decoratedCamera.seams == [decoration] && decoratedCamera.canvas == mainCamera.canvas
               && decoratedCamera.worldPoint(seam, into: local) == mainCamera.worldPoint(seam, into: local),
               "foreground metadata never shifts or rescales the panoramic camera")
        for invalid in [WorldSeam(boundaryX: .nan, lowerY: 0, upperY: 1080, roomOnRight: true),
                        WorldSeam(boundaryX: 0, lowerY: 400, upperY: 400, roomOnRight: true),
                        WorldSeam(boundaryX: 0, lowerY: 700, upperY: 300, roomOnRight: true),
                        WorldSeam(boundaryX: 0, lowerY: -.infinity, upperY: 1080, roomOnRight: true),
                        WorldSeam(boundaryX: 9000, lowerY: 0, upperY: 1080, roomOnRight: true),
                        WorldSeam(boundaryX: 0, lowerY: -1, upperY: 1080, roomOnRight: true)] {
            expect(WorldViewport(canvas: mainCamera.canvas, display: room, seams: [invalid]) == nil,
                   "invalid or out-of-canvas foreground edges cannot poison a viewport")
        }
        expect(WorldViewport(canvas: mainCamera.canvas, display: room,
               seams: Array(repeating: decoration, count: 129)) == nil,
               "unbounded foreground edge lists are rejected")

        expect(WorldViewport.make(display: room, among: []) == nil, "an absent screen inventory cannot fabricate a camera")
        expect(WorldViewport.make(display: left, among: [room]) == nil, "an unknown target screen is rejected")
        for corrupt in [CGRect.zero, CGRect(x: 0, y: 0, width: -1, height: 2),
                        CGRect(x: 0, y: 0, width: 2, height: 0),
                        CGRect(x: CGFloat.infinity, y: 0, width: 2, height: 2),
                        CGRect(x: 0, y: CGFloat.nan, width: 2, height: 2),
                        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 2)] {
            expect(WorldViewport(canvas: corrupt, display: room) == nil,
                   "invalid canvas geometry is rejected")
            expect(WorldViewport.make(display: room, among: [room, corrupt]) == nil,
                   "one invalid physical frame cannot poison the shared camera")
        }
        expect(WorldViewport(canvas: room, display: left) == nil,
               "a display outside its world canvas is rejected")
        print("PASS: \(checks) shared world viewport geometry and seam checks (synthetic screens only)")
    }
}
