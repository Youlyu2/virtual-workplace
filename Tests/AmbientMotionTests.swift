import Foundation
import CoreGraphics

@main
struct AmbientMotionTests {
    static var checks = 0
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }

    static func fixture(at now: Date) -> SceneSnapshot {
        var state = SceneSnapshot.empty(now: now)
        state.taskOrigin = .codex
        state.totalSessionCount = 1
        state.sourceMessage = "Offline test fixture"
        state.tasks = [WorkplaceTask(id: "real-task", title: "Task continues during a short walk", status: .running, slot: 2)]
        return state
    }

    static func poll(_ scheduler: AmbientEmployeeMotion, seconds: TimeInterval,
                     state: SceneSnapshot? = nil, action: SceneAction? = nil,
                     reduceMotion: Bool = false) -> SceneAction? {
        let now = start.addingTimeInterval(seconds)
        return scheduler.poll(snapshot: state ?? fixture(at: now), currentAction: action,
                              reduceMotion: reduceMotion, at: now)
    }

    static func main() throws {
        let scheduler = AmbientEmployeeMotion { $0 ? 75 : 150 }
        expect(poll(scheduler, seconds: 0) == nil, "working starts a quiet warmup, not an immediate walk")
        expect(poll(scheduler, seconds: 74.99) == nil, "warmup does not trigger early")
        let walk = poll(scheduler, seconds: 75)
        expect(walk?.kind == .walk && walk?.startedAt == start.addingTimeInterval(75),
               "the app emits one shared walk at its deadline")
        expect(poll(scheduler, seconds: 75, action: walk) == nil,
               "another update cannot restart a walk that is already active")
        expect(poll(scheduler, seconds: 94.99, action: walk) == nil, "the full walk is allowed to finish")
        expect(poll(scheduler, seconds: 244.99) == nil,
               "the next quiet interval is measured after the walk finishes")
        expect(poll(scheduler, seconds: 245)?.kind == .walk, "a later eligible interval can trigger another walk")

        let manual = AmbientEmployeeMotion { $0 ? 75 : 150 }
        _ = poll(manual, seconds: 0)
        let coffee = SceneAction(kind: .coffee, startedAt: start.addingTimeInterval(74))
        expect(poll(manual, seconds: 75, action: coffee) == nil, "automatic walking cannot interrupt a manual gesture")
        manual.postpone(at: start.addingTimeInterval(74))
        expect(poll(manual, seconds: 80) == nil && poll(manual, seconds: 223.99) == nil,
               "manual playback postpones walking instead of immediately chaining into it")
        expect(poll(manual, seconds: 224)?.kind == .walk, "manual postponement retains a later walking opportunity")

        for mode in [EmployeeMode.sitting, .standing, .slacking] {
            let scheduler = AmbientEmployeeMotion { $0 ? 75 : 150 }
            _ = poll(scheduler, seconds: 0)
            var state = fixture(at: start.addingTimeInterval(75)); state.mode = mode
            expect(poll(scheduler, seconds: 75, state: state) == nil, "explicit \(mode) remains authoritative")
            expect(poll(scheduler, seconds: 76) == nil && poll(scheduler, seconds: 150.99) == nil,
                   "returning from explicit \(mode) receives a new warmup")
            expect(poll(scheduler, seconds: 151)?.kind == .walk, "automatic mode can walk after \(mode) ends")
        }

        for reason in ["waiting", "failed", "idle", "completed", "empty", "offline", "stale", "demo", "reduced"] {
            let scheduler = AmbientEmployeeMotion { $0 ? 75 : 150 }
            _ = poll(scheduler, seconds: 0)
            var state = fixture(at: start.addingTimeInterval(75))
            switch reason {
            case "waiting": state.tasks[0].status = .waiting
            case "failed": state.tasks[0].status = .failed
            case "idle": state.tasks[0].status = .idle
            case "completed": state.tasks[0].status = .completed
            case "empty": state.tasks = []
            case "offline": state.isOnline = false
            case "stale": state.updatedAt = start
            case "demo": state.demoRunning = true
            default: break
            }
            expect(poll(scheduler, seconds: 75, state: state, reduceMotion: reason == "reduced") == nil,
                   "\(reason) does not schedule a walk")
            expect(poll(scheduler, seconds: 76) == nil && poll(scheduler, seconds: 150.99) == nil,
                   "leaving \(reason) cannot resume an old overdue walk")
        }

        let missed = AmbientEmployeeMotion { $0 ? 75 : 150 }
        _ = poll(missed, seconds: 0)
        expect(poll(missed, seconds: 80) == nil, "five seconds late discards a missed deadline")
        expect(poll(missed, seconds: 81) == nil && poll(missed, seconds: 155.99) == nil,
               "a stalled runloop starts another quiet warmup")
        expect(poll(missed, seconds: 156)?.kind == .walk, "a stalled runloop can recover naturally")
        missed.reset()
        expect(poll(missed, seconds: 200) == nil, "sleep/wake reset cannot instantly replay the previous timer")

        verifyRoute("stroll", sample: AmbientEmployeeMotion.walkSample,
                    duration: 20, xRange: 730...1020, yRange: 110...270,
                    totalDistance: 900, expectedDirections: Set(PixelWalkDirection.allCases))
        verifyRoute("cat visit", sample: AmbientEmployeeMotion.catVisitSample,
                    duration: 12, xRange: 740...835, yRange: 100...270,
                    totalDistance: 530, expectedDirections: Set(PixelWalkDirection.allCases))
        for progress: CGFloat in [-1, 0, 0.02, 0.98, 1, 2, .nan, .infinity, -.infinity] {
            let pose = AmbientEmployeeMotion.walkSample(progress: progress)
            expect(pose.feet == CGPoint(x: 835, y: 270) && !pose.isMoving && pose.direction == .up,
                   "invalid, outside and settle progress hold at the chair in a stable rear pose")
            expect(AmbientEmployeeMotion.walkFeet(progress: progress) == pose.feet,
                   "legacy feet-only callers use the same cardinal route")
        }
        let expectedCorners: [Int: (CGPoint, PixelWalkDirection)] = [
            60: (CGPoint(x: 835, y: 210), .right),
            245: (CGPoint(x: 1020, y: 210), .down),
            345: (CGPoint(x: 1020, y: 110), .left),
            635: (CGPoint(x: 730, y: 110), .up),
            735: (CGPoint(x: 730, y: 210), .right),
            840: (CGPoint(x: 835, y: 210), .up)
        ]
        var paused: [Int: Int] = [:]
        var turnsFaceTheNextLeg = true
        for index in 0...2000 {
            let pose = AmbientEmployeeMotion.walkSample(progress: CGFloat(index) / 2000)
            let marker = Int(pose.distance.rounded())
            if !pose.isMoving, let expected = expectedCorners[marker] {
                paused[marker, default: 0] += 1
                turnsFaceTheNextLeg = turnsFaceTheNextLeg && pose.feet == expected.0 && pose.direction == expected.1
            }
        }
        expect(turnsFaceTheNextLeg, "turns plant feet at the corner and face the next leg before moving")
        expect(paused.count == 6 && paused.values.allSatisfy { (10...20).contains($0) },
               "all six corners include a short stationary turn instead of sliding through a curve")
        for progress: CGFloat in [0.35, 0.5, 0.65] {
            let pose = AmbientEmployeeMotion.catVisitSample(progress: progress)
            expect(pose.feet == CGPoint(x: 740, y: 100) && pose.direction == .left && !pose.isMoving,
                   "the middle of a cat visit is stationary and faces the cat")
        }
        expect(AmbientEmployeeMotion.catVisitSample(progress: 1).feet == CGPoint(x: 835, y: 270)
               && AmbientEmployeeMotion.catVisitSample(progress: 1).direction == .up,
               "the cat visit also returns to the exact chair with the rear toward the desk")

        var state = fixture(at: start)
        let before = state
        state.action = SceneAction(kind: .walk, startedAt: start)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("VirtualWorkplaceWalk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = StateStore(url: temporary.appendingPathComponent("state.json"))
        try store.write(state)
        let decoded = try store.read()
        expect(decoded == state, "other hosts receive the same walk identifier and timeline")
        expect(decoded.tasks == before.tasks && decoded.taskOrigin == before.taskOrigin
               && decoded.totalSessionCount == before.totalSessionCount && decoded.mode == before.mode,
               "walking does not change real task status, source or posture preferences")
        expect(decoded.action?.isActive(at: start.addingTimeInterval(20)) == false,
               "another host cannot replay a completed walk")

        var randomBounds = true
        for _ in 0..<10 {
            let random = AmbientEmployeeMotion()
            _ = poll(random, seconds: 0)
            var deadline: Int?
            for second in 1...121 where deadline == nil {
                if poll(random, seconds: Double(second)) != nil { deadline = second }
            }
            randomBounds = randomBounds && deadline.map { (75...120).contains($0) } == true
        }
        expect(randomBounds, "production random warmup remains within its declared bounds")
        print("PASS: \(checks) ambient-walk scheduling, manual precedence, safe path and shared-state checks; no UI or user state touched")
    }

    static func verifyRoute(_ name: String, sample: (CGFloat) -> EmployeeWalkSample, duration: CGFloat,
                            xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>,
                            totalDistance: CGFloat, expectedDirections: Set<PixelWalkDirection>) {
        var safe = true, continuous = true, cardinal = true, matchesHeading = true
        var monotonicDistance = true, footfallsFollowDistance = true, constantSpeed = true
        var actualDirections: Set<PixelWalkDirection> = []
        var previous = sample(0)
        var movingSpeed: CGFloat?
        for index in 1...2000 {
            let pose = sample(CGFloat(index) / 2000)
            let dx = pose.feet.x - previous.feet.x, dy = pose.feet.y - previous.feet.y
            let distance = abs(dx) + abs(dy)
            safe = safe && pose.feet.x.isFinite && pose.feet.y.isFinite
                && xRange.contains(pose.feet.x) && yRange.contains(pose.feet.y)
            continuous = continuous && hypot(dx, dy) < 2
            cardinal = cardinal && (abs(dx) < 0.00001 || abs(dy) < 0.00001)
            monotonicDistance = monotonicDistance && pose.distance + 0.00001 >= previous.distance
            footfallsFollowDistance = footfallsFollowDistance && abs((pose.distance - previous.distance) - distance) < 0.00001
            if pose.isMoving {
                actualDirections.insert(pose.direction)
                if abs(dx) > 0.00001 { matchesHeading = matchesHeading && pose.direction == (dx > 0 ? .right : .left) }
                if abs(dy) > 0.00001 { matchesHeading = matchesHeading && pose.direction == (dy > 0 ? .up : .down) }
                if previous.isMoving && previous.direction == pose.direction {
                    let speed = distance / (duration / 2000)
                    if let movingSpeed { constantSpeed = constantSpeed && abs(speed - movingSpeed) < 0.0001 }
                    else { movingSpeed = speed }
                }
            }
            previous = pose
        }
        expect(safe, "\(name) stays in the open floor away from furniture and cat")
        expect(continuous, "\(name) has no position jumps")
        expect(cardinal, "\(name) never travels diagonally")
        expect(matchesHeading && actualDirections == expectedDirections, "\(name) faces every actual travel direction")
        expect(monotonicDistance && footfallsFollowDistance, "\(name) footfall timing follows physical travel, including pauses")
        expect(constantSpeed && movingSpeed != nil, "\(name) moves at a steady speed between corners")
        expect(previous.feet == sample(0).feet && !previous.isMoving
               && abs(previous.distance - totalDistance) < 0.00001, "\(name) returns exactly to its initial feet position")
    }
}
