import Foundation

@main enum AgentPuppetTests {
    private static var checks = 0
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), "FAIL: \(message)")
    }
    private static func near(_ a: Double, _ b: Double, _ message: String) {
        expect(abs(a - b) < 1e-8, message)
    }
    private static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure("FAIL: expected rejection: \(message)") }
        catch { checks += 1 }
    }
    private static func track(_ end: AgentPose, duration: Double = 3) -> AgentTimeline {
        AgentTimeline(startedAt: now, frames: [AgentKeyframe(time: 0, pose: .neutral),
                                             AgentKeyframe(time: duration, pose: end)])
    }

    static func main() throws {
        try AgentPose.neutral.validate()
        expect(AgentJoint.allCases.count == 12, "the body exposes twelve independently addressable joints")
        var target = AgentPose.neutral
        target.facing = .front
        target.joints = ["leftShoulder": -37.25, "leftElbow": 68.75, "leftWrist": 14.5,
                         "rightShoulder": 102.25, "rightElbow": -47.125, "rightWrist": -9.5,
                         "leftHip": 13.25, "leftKnee": -23.5, "rightHip": -17.75,
                         "rightKnee": 31.5, "torsoLean": 12.75, "headTilt": -18.5]
        target.face = AgentFace(eyes: 0.24, brows: -0.375, mouth: 0.8125, mouthOpen: 0.42)
        let validatedTarget = try target.validated()
        expect(validatedTarget == target, "arbitrary fractional joint and expression targets survive validation verbatim")
        let trajectory = track(target)
        try trajectory.validate()
        expect(trajectory.sample(at: now.addingTimeInterval(-1)) == .neutral, "future trajectories hold their first pose")
        expect(trajectory.sample(at: now) == .neutral, "the first absolute-time frame is exact")
        expect(trajectory.sample(at: now.addingTimeInterval(3)) == target, "the terminal pose is exact")
        expect(trajectory.sample(at: now.addingTimeInterval(1_000_000)) == target, "finished trajectories hold a bounded final pose")
        let middle = trajectory.sample(at: now.addingTimeInterval(1.5))
        for joint in AgentJoint.allCases { near(middle.angle(joint), target.angle(joint) / 2, "\(joint) interpolates independently") }
        near(middle.face.eyes, 0.62, "eyes interpolate continuously")
        near(middle.face.brows, -0.1875, "brows interpolate continuously")
        near(middle.face.mouth, 0.40625, "mouth curvature interpolates continuously")
        near(middle.face.mouthOpen, 0.21, "mouth opening interpolates continuously")
        expect(trajectory.sample(at: now.addingTimeInterval(0.1), reduceMotion: true) == target,
               "reduced motion presents the final target without continuous animation")

        var destination = AgentPose.neutral
        destination.x += 100; destination.y += 40; destination.facing = .front
        let walk = track(destination, duration: 2.8)
        try walk.validate()
        let east = walk.sample(at: now.addingTimeInterval(1))
        near(east.x, 885, "cardinal path advances horizontally first")
        near(east.y, 270, "horizontal travel holds Y")
        expect(east.facing == .right, "travel faces the horizontal direction")
        let north = walk.sample(at: now.addingTimeInterval(2.5))
        near(north.x, 935, "vertical travel starts only after the X destination")
        near(north.y, 295, "the vertical segment uses the remaining Manhattan distance")
        expect(north.facing == .back, "upward travel shows the back")
        var previous = walk.sample(at: now)
        for index in 1...300 {
            let current = walk.sample(at: now.addingTimeInterval(Double(index) / 100))
            // A discrete sample can straddle the corner. Each point itself
            // must still lie on one of the two cardinal route segments.
            expect(abs(current.y - 270) < 1e-8 || abs(current.x - 935) < 1e-8,
                   "root trajectory never interpolates diagonally")
            expect(abs(current.x - previous.x) + abs(current.y - previous.y) <= 1.500001,
                   "cardinal movement has bounded constant travel speed")
            previous = current
        }
        for (x, y, facing): (Double, Double, AgentFacing) in [(735, 270, .left), (835, 210, .front)] {
            var end = AgentPose.neutral; end.x = x; end.y = y
            expect(track(end).sample(at: now.addingTimeInterval(1.5)).facing == facing,
                   "the opposite cardinal direction has its own facing")
        }
        near(AgentTimeline.minimumDuration(from: .neutral, to: destination), 140 / 160,
             "minimum movement time includes both cardinal legs")

        for joint in AgentJoint.allCases {
            for value in [joint.limits.lowerBound, joint.limits.upperBound] {
                var pose = AgentPose.neutral; pose.joints[joint.rawValue] = value
                try pose.validate()
                checks += 1
            }
            var pose = AgentPose.neutral; pose.joints[joint.rawValue] = joint.limits.upperBound + 0.001
            rejects("every joint enforces its own limit") { try pose.validate() }
            pose.joints[joint.rawValue] = .nan
            rejects("NaN joints cannot reach drawing") { try pose.validate() }
        }
        var invalid = AgentPose.neutral
        invalid.joints["inventedJoint"] = 10
        rejects("unknown joint keys cannot expand the state") { try invalid.validate() }
        invalid = .neutral; invalid.x = 459.99
        rejects("root outside the walkable floor") { try invalid.validate() }
        invalid = .neutral; invalid.y = .infinity
        rejects("infinite root") { try invalid.validate() }
        invalid = .neutral; invalid.face.eyes = 1.01
        rejects("invalid eye opening") { try invalid.validate() }
        invalid = .neutral; invalid.face.brows = -1.01
        rejects("invalid brow parameter") { try invalid.validate() }
        invalid = .neutral; invalid.face.mouth = .nan
        rejects("nonfinite expression") { try invalid.validate() }

        var bad = trajectory
        bad.frames = []
        rejects("empty timeline") { try bad.validate() }
        bad = trajectory; bad.frames[0].time = 0.01
        rejects("first frame starts at zero") { try bad.validate() }
        bad = trajectory; bad.frames[1].time = 0
        rejects("duplicate frame clocks") { try bad.validate() }
        bad = trajectory; bad.frames[1].time = 15.001
        rejects("duration is bounded") { try bad.validate() }
        bad = trajectory; bad.frames[1].time = .nan
        rejects("nonfinite frame clock") { try bad.validate() }
        bad = trajectory; bad.startedAt = Date(timeIntervalSince1970: .infinity)
        rejects("nonfinite absolute start") { try bad.validate() }
        bad = trajectory; bad.id = String(repeating: "x", count: 129)
        rejects("bounded timeline identity") { try bad.validate() }
        bad = trajectory; bad.frames = (0...32).map { AgentKeyframe(time: Double($0) / 3, pose: .neutral) }
        rejects("more than32 frames cannot be retained") { try bad.validate() }
        bad.frames.removeLast(); try bad.validate()
        expect(bad.frames.count == 32, "the exact maximum frame count is accepted")
        var far = AgentPose.neutral; far.x = 1260
        rejects("root cannot teleport between keyframes") { try track(far, duration: 0.1).validate() }
        var turning = AgentPose.neutral; turning.joints["leftShoulder"] = 165
        rejects("joint speed is limited independently of angular range") { try track(turning, duration: 0.1).validate() }
        expect(bad.sample(at: Date(timeIntervalSince1970: .nan)) == .neutral,
               "invalid diagnostic clock has a finite neutral fallback")
        bad.frames[0].pose.x = .nan
        expect(bad.sample(at: now) == .neutral, "invalid in-memory poses do not reach the renderer")

        let encoded = try JSONEncoder().encode(trajectory)
        let copy = try JSONDecoder().decode(AgentTimeline.self, from: encoded)
        expect(copy == trajectory, "timeline roundtrip preserves arbitrary targets")
        for index in 0...300 {
            let clock = now.addingTimeInterval(Double(index) / 100)
            expect(copy.sample(at: clock) == trajectory.sample(at: clock), "independent hosts sample the same absolute trajectory")
        }
        var snapshot = SceneSnapshot.empty(now: now)
        let legacyData = try JSONEncoder().encode(snapshot)
        let legacy = try JSONDecoder().decode(SceneSnapshot.self, from: legacyData)
        expect(legacy.employeeControlMode == nil && legacy.agentTimeline == nil, "legacy snapshots retain automatic control")
        snapshot.employeeControlMode = .agent; snapshot.agentTimeline = trajectory
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-puppet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(url: root.appendingPathComponent("state.json"))
        try store.write(snapshot)
        let restored = try store.read()
        expect(restored == snapshot, "the shared state store carries the bounded agent trajectory")
        let validBytes = try Data(contentsOf: store.url)
        snapshot.agentTimeline?.frames[0].pose.face.mouthOpen = 1.5
        rejects("state validation rejects invalid agent fields") { try store.write(snapshot) }
        let afterRejected = try Data(contentsOf: store.url)
        expect(afterRejected == validBytes, "rejected control does not replace the last valid snapshot")
        print("PASS: \(checks) agent pose, cardinal interpolation, limits, schema and shared-state checks")
    }
}
