import Foundation
import CoreGraphics

enum PixelWalkDirection: String, CaseIterable, Hashable { case down, left, right, up }

struct EmployeeWalkSample: Equatable {
    var feet: CGPoint
    var direction: PixelWalkDirection
    var isMoving: Bool
    /// Actual distance travelled along the route, used to time the footfalls.
    var distance: CGFloat
}

/// The app is the only scheduler. Other hosts just read the shared SceneAction,
/// so opening a preview or another display never creates another walk.
final class AmbientEmployeeMotion {
    private var nextWalk: Date?
    private let interval: (Bool) -> TimeInterval

    init(interval: @escaping (Bool) -> TimeInterval = { first in
        first ? Double.random(in: 75...120) : Double.random(in: 150...300)
    }) { self.interval = interval }

    func reset() { nextWalk = nil }
    func postpone(at now: Date) { nextWalk = now.addingTimeInterval(interval(false)) }

    func poll(snapshot: SceneSnapshot, currentAction: SceneAction?, reduceMotion: Bool,
              at now: Date) -> SceneAction? {
        let eligible = !reduceMotion && snapshot.mode == .automatic && !snapshot.demoRunning
            && snapshot.isFresh(at: now) && snapshot.resolvedActivity(at: now) == .working
        guard eligible else { nextWalk = nil; return nil }
        if currentAction?.isActive(at: now) == true { return nil }
        guard let due = nextWalk else {
            nextWalk = now.addingTimeInterval(interval(true)); return nil
        }
        guard now >= due else { return nil }
        // A sleep/wake or a stopped runloop must not jump into an old walk.
        guard now.timeIntervalSince(due) < 5 else { reset(); return nil }
        nextWalk = now.addingTimeInterval(EmployeeAction.walk.duration + interval(false))
        return SceneAction(kind: .walk, startedAt: now)
    }

    private static let chairFeet = CGPoint(x: 835, y: 270)
    private static let stroll: [CGPoint] = [
        chairFeet, CGPoint(x: 835, y: 210), CGPoint(x: 1020, y: 210),
        CGPoint(x: 1020, y: 110), CGPoint(x: 730, y: 110),
        CGPoint(x: 730, y: 210), CGPoint(x: 835, y: 210), chairFeet
    ]
    private static let catApproach: [CGPoint] = [
        chairFeet, CGPoint(x: 835, y: 170), CGPoint(x: 740, y: 170), CGPoint(x: 740, y: 100)
    ]

    /// Every leg stays on a single axis. The pause at each corner lets the
    /// sprite plant its feet and turn before starting in the new direction.
    static func walkSample(progress: CGFloat) -> EmployeeWalkSample {
        let p = normalized(progress)
        return sample(path: stroll, seconds: p * 20, duration: 20,
                      startHold: 0.6, endHold: 0.6, startDirection: .up, endDirection: .up)
    }

    static func walkFeet(progress: CGFloat) -> CGPoint {
        walkSample(progress: progress).feet
    }

    /// Reuse the same four-direction rules when approaching the cat. The
    /// middle of the action is a stationary interaction, facing the cat.
    static func catVisitSample(progress: CGFloat) -> EmployeeWalkSample {
        let p = normalized(progress)
        let duration: CGFloat = 12
        let approachDuration = duration * 0.35
        let approachDistance = length(of: catApproach)
        if p < 0.35 {
            return sample(path: catApproach, seconds: p * duration, duration: approachDuration,
                          startHold: 0.4, endHold: 0, startDirection: .up, endDirection: .left)
        }
        if p <= 0.65 {
            return EmployeeWalkSample(feet: catApproach.last!, direction: .left,
                                      isMoving: false, distance: approachDistance)
        }
        var returning = sample(path: Array(catApproach.reversed()), seconds: (p - 0.65) * duration,
                               duration: approachDuration, startHold: 0, endHold: 0.4,
                               startDirection: .left, endDirection: .up)
        returning.distance += approachDistance
        return returning
    }

    private static func normalized(_ progress: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 0 }
        return max(0, min(1, progress))
    }

    private static func length(of points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { total, leg in
            total + abs(leg.1.x - leg.0.x) + abs(leg.1.y - leg.0.y)
        }
    }

    private static func heading(from start: CGPoint, to end: CGPoint) -> PixelWalkDirection {
        if end.x != start.x { return end.x > start.x ? .right : .left }
        return end.y > start.y ? .up : .down
    }

    private static func sample(path: [CGPoint], seconds: CGFloat, duration: CGFloat,
                               startHold: CGFloat, endHold: CGFloat,
                               startDirection: PixelWalkDirection,
                               endDirection: PixelWalkDirection) -> EmployeeWalkSample {
        let total = length(of: path)
        guard seconds > startHold else {
            return EmployeeWalkSample(feet: path[0], direction: startDirection, isMoving: false, distance: 0)
        }
        guard seconds < duration - endHold else {
            return EmployeeWalkSample(feet: path.last!, direction: endDirection, isMoving: false, distance: total)
        }
        let cornerPause: CGFloat = 0.14
        let movingTime = duration - startHold - endHold - CGFloat(path.count - 2) * cornerPause
        let speed = total / movingTime
        var elapsed = seconds - startHold
        var travelled: CGFloat = 0
        for index in 0..<(path.count - 1) {
            let a = path[index], b = path[index + 1]
            let legLength = abs(b.x - a.x) + abs(b.y - a.y)
            let legTime = legLength / speed
            let direction = heading(from: a, to: b)
            if elapsed < legTime {
                let distance = elapsed * speed
                var feet = a
                switch direction {
                case .down: feet.y -= distance
                case .left: feet.x -= distance
                case .right: feet.x += distance
                case .up: feet.y += distance
                }
                return EmployeeWalkSample(feet: feet, direction: direction, isMoving: true,
                                          distance: travelled + distance)
            }
            elapsed -= legTime
            travelled += legLength
            if index < path.count - 2 {
                if elapsed < cornerPause {
                    return EmployeeWalkSample(feet: b, direction: heading(from: b, to: path[index + 2]),
                                              isMoving: false, distance: travelled)
                }
                elapsed -= cornerPause
            }
        }
        return EmployeeWalkSample(feet: path.last!, direction: endDirection, isMoving: false, distance: total)
    }
}
