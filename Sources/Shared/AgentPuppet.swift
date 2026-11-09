import Foundation

/// Selecting Agent control grants ownership of the avatar pose only. Task
/// status, weather, notes, and the existing automatic animator stay separate.
enum EmployeeControlMode: String, Codable, CaseIterable { case automatic, agent }
enum AgentFacing: String, Codable, CaseIterable { case front, back, left, right }

/// Angles are degrees, measured from a limb hanging down; positive angles
/// point toward +X. Elbows/knees/wrists are relative to their parent segment.
enum AgentJoint: String, Codable, CaseIterable {
    case torsoLean, headTilt
    case leftShoulder, leftElbow, leftWrist, rightShoulder, rightElbow, rightWrist
    case leftHip, leftKnee, rightHip, rightKnee

    var limits: ClosedRange<Double> {
        switch self {
        case .torsoLean: return -30...30
        case .headTilt: return -35...35
        case .leftShoulder, .rightShoulder: return -165...165
        case .leftElbow, .rightElbow: return -155...155
        case .leftWrist, .rightWrist: return -90...90
        case .leftHip, .rightHip: return -70...70
        case .leftKnee, .rightKnee: return -130...130
        }
    }
}

enum AgentPuppetError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return "Agent 姿态不可用：\(reason)" }
    }
}

struct AgentFace: Codable, Equatable {
    var eyes: Double = 1
    var brows: Double = 0
    var mouth: Double = 0
    var mouthOpen: Double = 0

    func validate() throws {
        guard eyes.isFinite, brows.isFinite, mouth.isFinite, mouthOpen.isFinite,
              (0...1).contains(eyes), (-1...1).contains(brows),
              (-1...1).contains(mouth), (0...1).contains(mouthOpen) else {
            throw AgentPuppetError.invalid("表情参数超出范围")
        }
    }
}

/// Scene coordinates use the existing 1672×941 room plate. The root is the
/// floor anchor below the avatar, not a three-dimensional jump height.
struct AgentPose: Codable, Equatable {
    static let xRange: ClosedRange<Double> = 460...1260
    static let yRange: ClosedRange<Double> = 190...310
    static let neutral = AgentPose()

    var x: Double = 835
    var y: Double = 270
    var facing: AgentFacing = .back
    var joints: [String: Double] = [:]
    var face: AgentFace = AgentFace()

    func angle(_ joint: AgentJoint) -> Double { joints[joint.rawValue] ?? 0 }

    func validate() throws {
        guard x.isFinite, y.isFinite, Self.xRange.contains(x), Self.yRange.contains(y) else {
            throw AgentPuppetError.invalid("人物位置必须位于可行走地面")
        }
        guard joints.count <= AgentJoint.allCases.count else {
            throw AgentPuppetError.invalid("关节数量过多")
        }
        for (name, angle) in joints {
            guard let joint = AgentJoint(rawValue: name), angle.isFinite, joint.limits.contains(angle) else {
                throw AgentPuppetError.invalid("关节名称或角度不合法")
            }
        }
        try face.validate()
    }

    func validated() throws -> AgentPose { try validate(); return self }
}

struct AgentKeyframe: Codable, Equatable {
    var time: TimeInterval
    var pose: AgentPose
}

/// A bounded trajectory replaces the previous trajectory; there is no growing
/// command queue. Absolute dates keep desktop windows and the saver in sync.
struct AgentTimeline: Codable, Equatable, Identifiable {
    static let maximumFrames = 32
    static let maximumDuration: TimeInterval = 15
    static let maximumRootSpeed: Double = 160
    static let maximumAngularSpeed: Double = 360

    var id: String = UUID().uuidString
    var startedAt: Date
    var frames: [AgentKeyframe]

    var duration: TimeInterval { frames.last?.time ?? 0 }

    static func minimumDuration(from: AgentPose, to: AgentPose) -> TimeInterval {
        let travel = abs(to.x - from.x) + abs(to.y - from.y)
        let jointTravel = AgentJoint.allCases.map { abs(to.angle($0) - from.angle($0)) }.max() ?? 0
        guard travel.isFinite, jointTravel.isFinite else { return .infinity }
        return max(travel / maximumRootSpeed, jointTravel / maximumAngularSpeed)
    }

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 128 else {
            throw AgentPuppetError.invalid("轨迹标识不合法")
        }
        let start = startedAt.timeIntervalSince1970
        guard start.isFinite, start >= 0 else { throw AgentPuppetError.invalid("轨迹开始时间不合法") }
        guard !frames.isEmpty, frames.count <= Self.maximumFrames, frames[0].time == 0 else {
            throw AgentPuppetError.invalid("轨迹需要1至32帧，首帧时间为0")
        }
        for index in frames.indices {
            let frame = frames[index]
            guard frame.time.isFinite, (0...Self.maximumDuration).contains(frame.time) else {
                throw AgentPuppetError.invalid("轨迹不能超过15秒")
            }
            try frame.pose.validate()
            if index > 0 {
                let previous = frames[index - 1]
                let delta = frame.time - previous.time
                guard delta > 0 else { throw AgentPuppetError.invalid("关键帧时间必须递增") }
                guard delta + 1e-9 >= Self.minimumDuration(from: previous.pose, to: frame.pose) else {
                    throw AgentPuppetError.invalid("轨迹超过关节或行走速度上限")
                }
            }
        }
    }

    func sample(at now: Date, reduceMotion: Bool = false) -> AgentPose {
        // Defensive for diagnostic/in-memory callers; persisted trajectories
        // and local commands are validated before they reach the renderer.
        guard now.timeIntervalSince1970.isFinite, (try? validate()) != nil,
              let first = frames.first, let last = frames.last else { return .neutral }
        let elapsed = now.timeIntervalSince(startedAt)
        if elapsed <= 0 { return first.pose }
        if elapsed >= last.time || reduceMotion { return last.pose }
        guard let upper = frames.firstIndex(where: { $0.time >= elapsed }), upper > 0 else { return first.pose }
        let a = frames[upper - 1], b = frames[upper]
        let amount = (elapsed - a.time) / (b.time - a.time)
        return Self.interpolate(from: a.pose, to: b.pose, amount: amount)
    }

    private static func interpolate(from a: AgentPose, to b: AgentPose, amount: Double) -> AgentPose {
        let t = max(0, min(1, amount))
        if t == 0 { return a }
        if t == 1 { return b }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        var result = a
        let dx = b.x - a.x, dy = b.y - a.y
        let horizontal = abs(dx), vertical = abs(dy), total = horizontal + vertical
        if total > 0 {
            let travelled = total * t
            if travelled < horizontal {
                result.x = a.x + (dx < 0 ? -travelled : travelled)
                result.y = a.y
                result.facing = dx < 0 ? .left : .right
            } else {
                result.x = b.x
                let movedY = travelled - horizontal
                result.y = a.y + (dy < 0 ? -movedY : movedY)
                result.facing = vertical > 0 ? (dy < 0 ? .front : .back) : (dx < 0 ? .left : .right)
            }
        } else { result.facing = t < 0.5 ? a.facing : b.facing }
        for joint in AgentJoint.allCases { result.joints[joint.rawValue] = mix(a.angle(joint), b.angle(joint)) }
        result.face = AgentFace(eyes: mix(a.face.eyes, b.face.eyes), brows: mix(a.face.brows, b.face.brows),
                               mouth: mix(a.face.mouth, b.face.mouth), mouthOpen: mix(a.face.mouthOpen, b.face.mouthOpen))
        return result
    }
}
