import AppKit

@main
struct ManualActionTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }
    static func rejects(_ message: String, _ action: () throws -> Void) {
        do { try action(); fatalError("FAIL: expected rejection: \(message)") }
        catch { checks += 1 }
    }

    static func main() throws {
        _ = NSApplication.shared
        let now = Date()
        for kind in EmployeeAction.allCases {
            let action = SceneAction(kind: kind, startedAt: now)
            expect(action.isActive(at: now) && action.isActive(at: now.addingTimeInterval(kind.duration - 0.001)),
                   "\(kind.rawValue) remains active throughout its duration")
            expect(!action.isActive(at: now.addingTimeInterval(kind.duration)),
                   "\(kind.rawValue) expires at its boundary")
        }
        let action = SceneAction(kind: .coffee, startedAt: now)
        expect(!action.isActive(at: now.addingTimeInterval(-1)), "future actions cannot replay early")
        expect(action.progress(at: now.addingTimeInterval(-1)) == 0
               && action.progress(at: now.addingTimeInterval(20)) == 1, "action progress is bounded outside its playback window")

        var state = SceneSnapshot.empty(now: now)
        state.taskOrigin = .codex
        state.sourceMessage = "真实来源夹具，不启动观察器"
        state.totalSessionCount = 1
        state.mode = .slacking
        state.preferredPosture = .standing
        state.tasks = [WorkplaceTask(id: "real-thread", title: "保持真实任务状态", status: .running, slot: 2)]
        state.completedToday = 3
        let original = state
        state.action = action

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VirtualWorkplaceManualActions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("state.json"))
        try store.write(state)
        let restored = try store.read()
        expect(restored == state, "the shared snapshot preserves action identity and timing across processes")
        expect(restored.tasks == original.tasks && restored.taskOrigin == original.taskOrigin
               && restored.totalSessionCount == original.totalSessionCount && restored.completedToday == original.completedToday
               && restored.sourceMessage == original.sourceMessage && restored.mode == original.mode
               && restored.preferredPosture == original.preferredPosture,
               "manual playback does not rewrite real tasks, statistics, source metadata or posture preferences")
        expect(restored.action?.isActive(at: now.addingTimeInterval(20)) == false,
               "an old shared action cannot restart when another host reads it later")

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        legacy.removeValue(forKey: "action")
        let migrated = try JSONDecoder().decode(SceneSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(migrated.action == nil && migrated.tasks == state.tasks, "snapshots without the optional action remain readable")
        var invalid = state
        invalid.action?.id = ""
        rejects("empty action identifier") { try store.write(invalid) }
        invalid = state
        invalid.action?.id = String(repeating: "a", count: 129)
        rejects("oversized action identifier") { try store.write(invalid) }
        invalid = state
        invalid.action?.startedAt = Date(timeIntervalSince1970: -1)
        rejects("negative action timestamp") { try store.write(invalid) }
        invalid = state
        invalid.action?.startedAt = Date(timeIntervalSince1970: .nan)
        rejects("nonfinite action timestamp") { try store.write(invalid) }
        var unknown = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        var unknownAction = unknown["action"] as! [String: Any]
        unknownAction["kind"] = "unsupported-action"
        unknown["action"] = unknownAction
        rejects("unsupported action cannot enter the renderer") {
            _ = try JSONDecoder().decode(SceneSnapshot.self, from: JSONSerialization.data(withJSONObject: unknown))
        }

        expect(EmployeeActionSprites.isAvailable && PixelCat.hasSprites
               && (RoomAssets.usesFlatForeground || RoomAssets.rugPatch != nil),
               "production action and cat resources load for host rendering")
        if RoomAssets.usesFlatForeground {
            expect(RoomAssets.rugPatch == nil && RoomAssets.nightBackground == nil,
                   "the flat room cannot be covered by legacy perspective rug or night plates")
        }
        var poses = Set<UInt64>()
        for kind in EmployeeAction.allCases {
            var fixture = state
            fixture.action = SceneAction(kind: kind, startedAt: now)
            poses.insert(sceneFingerprint(fixture, at: now.addingTimeInterval(kind.duration * 0.45), time: 2))
        }
        expect(poses.count == EmployeeAction.allCases.count, "each action produces a distinct visible employee pose")
        var expired = state
        expired.action = SceneAction(kind: .wave, startedAt: now)
        var noAction = state
        noAction.action = nil
        let end = now.addingTimeInterval(EmployeeAction.wave.duration + 0.01)
        expect(sceneFingerprint(expired, at: end, time: 2) == sceneFingerprint(noAction, at: end, time: 2),
               "expired playback restores the original resting scene without a stuck action sprite")
        var waving = state
        waving.action = SceneAction(kind: .wave, startedAt: now)
        expect(sceneFingerprint(waving, at: now.addingTimeInterval(1), time: 1, reduceMotion: true)
               == sceneFingerprint(waving, at: now.addingTimeInterval(2), time: 10, reduceMotion: true),
               "reduced motion keeps a recognizable action pose without a looping gesture")
        expect(sceneFingerprint(waving, at: now.addingTimeInterval(1), time: 1)
               != sceneFingerprint(waving, at: now.addingTimeInterval(2), time: 2),
               "ordinary playback moves the gesture instead of displaying only a static swap")
        expect(catFingerprint(time: 1, reduceMotion: true) == catFingerprint(time: 26, reduceMotion: true),
               "reduced motion pauses the cat's automatic movement cycle")
        expect(catFingerprint(time: 1, reduceMotion: false) != catFingerprint(time: 26, reduceMotion: false),
               "the independent cat changes posture and position over its cycle")
        print("PASS: \(checks) manual action, shared state and reduced-motion checks; no user state or live observer touched")
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func sceneFingerprint(_ state: SceneSnapshot, at now: Date, time: TimeInterval,
                                         reduceMotion: Bool = false) -> UInt64 {
        let canvas = context(width: 1672, height: 941)
        SceneRenderer.draw(in: canvas, bounds: CGRect(x: 0, y: 0, width: 1672, height: 941),
                           snapshot: state, time: time, reduceMotion: reduceMotion, now: now)
        // Compare the actor and chair, excluding the changing wall clock.
        return fingerprint(canvas, region: CGRect(x: 640, y: 250, width: 400, height: 480))
    }
    private static func catFingerprint(time: TimeInterval, reduceMotion: Bool) -> UInt64 {
        let canvas = context(width: 840, height: 240)
        PixelCat.draw(in: canvas, time: time, interaction: nil, reduceMotion: reduceMotion)
        return fingerprint(canvas, region: CGRect(x: 500, y: 50, width: 250, height: 160))
    }
    private static func fingerprint(_ context: CGContext, region: CGRect) -> UInt64 {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 1469598103934665603
        for y in stride(from: Int(region.minY), to: Int(region.maxY), by: 2) {
            for x in stride(from: Int(region.minX), to: Int(region.maxX), by: 2) {
                let index = ((context.height - 1 - y) * context.width + x) * 4
                for channel in 0..<4 { hash = (hash ^ UInt64(bytes[index + channel])) &* 1099511628211 }
            }
        }
        return hash
    }
}
