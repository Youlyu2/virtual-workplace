import Foundation
import CoreFoundation
import Darwin

/// A single bounded local mailbox controls the avatar only. The existing app
/// heartbeat polls it; there is no network listener or extra animation timer.
final class AgentControlInbox {
    private(set) var mode: EmployeeControlMode
    private(set) var timeline: AgentTimeline?
    private(set) var lastError: String?
    var onChange: (() -> Void)?
    let directory: URL
    private var lastID: String?
    private var recentIDs: [(String, Date)] = []
    private let limit = 65_536

    init(directory: URL, mode: EmployeeControlMode = .automatic, timeline: AgentTimeline? = nil) {
        self.directory = directory; self.mode = mode; self.timeline = timeline
        if let previous = try? Self.readObject(directory.appendingPathComponent("agent-result.json"), limit: 65_536) {
            lastID = previous["id"] as? String
        }
    }

    func setMode(_ value: EmployeeControlMode, at now: Date = Date()) {
        mode = value
        if mode == .agent, timeline == nil {
            timeline = AgentTimeline(startedAt: now, frames: [AgentKeyframe(time: 0, pose: .neutral)])
        }
        lastError = nil; onChange?(); publishStatus(at: now)
    }

    func poll(at now: Date = Date()) {
        let url = directory.appendingPathComponent("agent-command.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let command = try Self.readObject(url, limit: limit)
                guard let id = command["id"] as? String, UUID(uuidString: id) != nil else {
                    throw AgentPuppetError.invalid("本地指令需要 UUID 标识")
                }
                guard id != lastID else { publishStatus(at: now); return }
                recentIDs.removeAll { now.timeIntervalSince($0.1) > 15 }
                if recentIDs.contains(where: { $0.0 == id }) {
                    write(["id": id, "ok": false, "error": "重复的本地指令已忽略"], name: "agent-result.json")
                    publishStatus(at: now); return
                }
                lastID = id
                recentIDs.append((id, now))
                if recentIDs.count > 64 { recentIDs.removeFirst(recentIDs.count - 64) }
                do {
                    let issued = try Self.number(command["issuedAt"])
                    guard (-2...15).contains(now.timeIntervalSince1970 - issued) else {
                        throw AgentPuppetError.invalid("指令已过期，请重新发送")
                    }
                    lastError = nil
                    let result = try apply(command, at: now)
                    write(["id": id, "ok": true, "result": result], name: "agent-result.json")
                } catch {
                    lastError = error.localizedDescription
                    write(["id": id, "ok": false, "error": error.localizedDescription], name: "agent-result.json")
                }
            } catch { lastError = error.localizedDescription }
        }
        publishStatus(at: now)
    }

    /// Kept independent of file IO for isolated protocol and replay tests.
    func apply(_ command: [String: Any], at now: Date) throws -> [String: Any] {
        guard let op = command["op"] as? String else { throw AgentPuppetError.invalid("缺少 op") }
        switch op {
        case "status": break
        case "mode":
            guard let raw = command["mode"] as? String, let value = EmployeeControlMode(rawValue: raw) else {
                throw AgentPuppetError.invalid("模式应为 automatic 或 agent")
            }
            setMode(value, at: now)
        case "pose":
            try requireControl()
            guard let patch = command["pose"] as? [String: Any] else { throw AgentPuppetError.invalid("缺少 pose 参数") }
            let current = timeline?.sample(at: now) ?? .neutral
            let target = try Self.patched(current, with: patch)
            let requested = try command["duration"].map { try Self.number($0) } ?? 1.5
            guard requested.isFinite, requested > 0, requested <= AgentTimeline.maximumDuration else {
                throw AgentPuppetError.invalid("过渡时间应大于0且不超过15秒")
            }
            let duration = max(requested, AgentTimeline.minimumDuration(from: current, to: target))
            let next = AgentTimeline(startedAt: now, frames: [AgentKeyframe(time: 0, pose: current), AgentKeyframe(time: duration, pose: target)])
            try next.validate(); timeline = next; onChange?()
        case "sequence":
            try requireControl()
            guard let frames = command["frames"] as? [[String: Any]], !frames.isEmpty,
                  frames.count < AgentTimeline.maximumFrames else {
                throw AgentPuppetError.invalid("需要1至31个目标关键帧")
            }
            var pose = timeline?.sample(at: now) ?? .neutral
            var samples = [AgentKeyframe(time: 0, pose: pose)]
            for frame in frames {
                guard let patch = frame["pose"] as? [String: Any] else {
                    throw AgentPuppetError.invalid("关键帧需要 time 和 pose")
                }
                let time = try Self.number(frame["time"])
                pose = try Self.patched(pose, with: patch)
                samples.append(AgentKeyframe(time: time, pose: pose))
            }
            let next = AgentTimeline(startedAt: now, frames: samples)
            try next.validate(); timeline = next; onChange?()
        default: throw AgentPuppetError.invalid("未知本地操作")
        }
        return status(at: now)
    }

    func status(at now: Date = Date()) -> [String: Any] {
        let pose = timeline?.sample(at: now) ?? .neutral
        let object = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(pose))) ?? [:]
        let limits = Dictionary(uniqueKeysWithValues: AgentJoint.allCases.map { ($0.rawValue, [$0.limits.lowerBound, $0.limits.upperBound]) })
        return ["mode": mode.rawValue, "pose": object, "updatedAt": now.timeIntervalSince1970,
                "trajectoryID": timeline?.id ?? "", "duration": timeline?.duration ?? 0,
                "capabilities": ["jointLimits": limits, "face": ["eyes": [0, 1], "brows": [-1, 1], "mouth": [-1, 1], "mouthOpen": [0, 1]],
                    "floor": ["x": [AgentPose.xRange.lowerBound, AgentPose.xRange.upperBound], "y": [AgentPose.yRange.lowerBound, AgentPose.yRange.upperBound]],
                    "maximumFrames": AgentTimeline.maximumFrames, "maximumDuration": AgentTimeline.maximumDuration,
                    "facing": AgentFacing.allCases.map(\.rawValue), "angles": "degrees; zero points down, positive points toward +X",
                    "movement": "cardinal X then Y; model supplies limb motion"],
                "error": lastError ?? ""]
    }

    private func requireControl() throws {
        guard mode == .agent else { throw AgentPuppetError.invalid("请先切换到 Agent 接管模式") }
    }

    static func patched(_ original: AgentPose, with patch: [String: Any]) throws -> AgentPose {
        guard Set(patch.keys).isSubset(of: ["x", "y", "facing", "joints", "face"]) else {
            throw AgentPuppetError.invalid("未知姿态字段")
        }
        var pose = original
        if patch["x"] != nil { pose.x = try Self.number(patch["x"]) }
        if patch["y"] != nil { pose.y = try Self.number(patch["y"]) }
        if let raw = patch["facing"] {
            guard let text = raw as? String, let facing = AgentFacing(rawValue: text) else { throw AgentPuppetError.invalid("朝向不合法") }
            pose.facing = facing
        }
        if let raw = patch["joints"] {
            guard let joints = raw as? [String: Any] else { throw AgentPuppetError.invalid("关节参数必须为对象") }
            for (name, value) in joints { pose.joints[name] = try Self.number(value) }
        }
        if let raw = patch["face"] {
            guard let face = raw as? [String: Any], Set(face.keys).isSubset(of: ["eyes", "brows", "mouth", "mouthOpen"]) else {
                throw AgentPuppetError.invalid("表情参数不合法")
            }
            if face["eyes"] != nil { pose.face.eyes = try Self.number(face["eyes"]) }
            if face["brows"] != nil { pose.face.brows = try Self.number(face["brows"]) }
            if face["mouth"] != nil { pose.face.mouth = try Self.number(face["mouth"]) }
            if face["mouthOpen"] != nil { pose.face.mouthOpen = try Self.number(face["mouthOpen"]) }
        }
        return try pose.validated()
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw AgentPuppetError.invalid("姿态参数必须是有限数值")
        }
        return value.doubleValue
    }

    private func publishStatus(at date: Date) { write(status(at: date), name: "agent-status.json") }
    private func write(_ object: [String: Any], name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard data.count <= limit else { return }
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { lastError = "本地控制状态无法写入：\(error.localizedDescription)" }
    }

    private static func readObject(_ url: URL, limit: Int) throws -> [String: Any] {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw AgentPuppetError.invalid("无法读取本地指令") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_size > 0, info.st_size <= limit else {
            throw AgentPuppetError.invalid("本地指令文件不合法或过大")
        }
        var bytes = [UInt8](repeating: 0, count: limit + 1)
        let count = read(fd, &bytes, bytes.count)
        guard count > 0, count <= limit,
              let object = try JSONSerialization.jsonObject(with: Data(bytes.prefix(count))) as? [String: Any] else {
            throw AgentPuppetError.invalid("本地指令需要 JSON 对象")
        }
        return object
    }
}
