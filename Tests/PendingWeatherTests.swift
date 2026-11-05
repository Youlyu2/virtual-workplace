import Foundation

@main
enum PendingWeatherTests {
    static var checks = 0
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    static func snapshot(age: TimeInterval, pace: PendingWeatherPace = .balanced) -> SceneSnapshot {
        var result = SceneSnapshot.empty(now: now)
        result.world = SceneWorld(weather: .snow, timeMode: .night, pendingWeatherPace: pace)
        result.pendingNotes = [PendingNote(id: "oldest", text: "等候交办", createdAt: now.addingTimeInterval(-age), slot: 0)]
        return result
    }
    static func main() throws {
        expect(SceneWorld().pendingWeatherEnabled && SceneWorld().pendingWeatherPace == .balanced,
               "user-selected 1h/4h schedule is the enabled default")
        expect(PendingWeatherPace.balanced.cloudyAfter == 3600 && PendingWeatherPace.balanced.rainAfter == 9000
               && PendingWeatherPace.balanced.stormAfter == 14400, "balanced thresholds match 1h / 2h30m / 4h")
        let legacy = try JSONDecoder().decode(SceneWorld.self, from: Data("{\"weather\":\"snow\",\"timeMode\":\"night\"}".utf8))
        expect(legacy.weather == .snow && legacy.timeMode == .night && legacy.pendingWeatherEnabled
               && legacy.pendingWeatherPace == .balanced, "legacy preferences gain the policy without losing base weather")
        var disabled = legacy
        disabled.pendingWeatherEnabled = false; disabled.pendingWeatherPace = .relaxed
        let restored = try JSONDecoder().decode(SceneWorld.self, from: JSONEncoder().encode(disabled))
        expect(restored == disabled,
               "disabled policy and alternate schedule round-trip")
        for pace in PendingWeatherPace.allCases {
            expect(pace.cloudyAfter > 0 && pace.cloudyAfter < pace.rainAfter && pace.rainAfter < pace.stormAfter,
                   "\(pace) has ordered thresholds")
            let cases: [(TimeInterval, PendingWeatherStage, WorldWeather)] = [
                (0, .none, .snow), (pace.cloudyAfter - 0.001, .none, .snow),
                (pace.cloudyAfter, .cloudy, .cloudy), (pace.rainAfter - 0.001, .cloudy, .cloudy),
                (pace.rainAfter, .rain, .rain), (pace.stormAfter - 0.001, .rain, .rain),
                (pace.stormAfter, .thunderstorm, .thunderstorm), (pace.stormAfter * 2, .thunderstorm, .thunderstorm)]
            for (age, stage, weather) in cases {
                let source = snapshot(age: age, pace: pace)
                let effect = source.pendingWeatherEffect(at: now)
                expect(effect.stage == stage && effect.weather == weather, "\(pace) exact boundary \(age)")
                expect(abs(effect.oldestWait - age) < 0.001, "waiting uses the original creation date")
                let resolved = source.effectiveWorld(at: now)
                expect(resolved.weather == weather && source.world?.weather == .snow && resolved.timeMode == .night,
                       "derived weather preserves base choice and daylight")
                expect((effect.reason != nil) == (stage != .none), "only an active override explains an overdue cause")
            }
        }
        var queue = snapshot(age: 20_000)
        queue.pendingNotes?.append(PendingNote(id: "young", text: "新待办", createdAt: now.addingTimeInterval(-30), slot: 1))
        let before = try JSONEncoder().encode(queue)
        let originalEffect = queue.pendingWeatherEffect(at: now)
        queue.pendingNotes?.reverse()
        expect(queue.pendingWeatherEffect(at: now) == originalEffect, "array order does not change the oldest pending request")
        queue.pendingNotes = queue.pendingNotes?.filter { $0.id == "young" }
        expect(queue.effectiveWorld(at: now).weather == .snow, "handing off oldest restores base with only young notes")
        queue.pendingNotes = []
        expect(queue.effectiveWorld(at: now).weather == .snow, "empty inbox restores base")
        queue.pendingNotes = nil
        expect(queue.pendingWeatherEffect(at: now).stage == .none, "legacy snapshots without notes have no override")
        queue = try JSONDecoder().decode(SceneSnapshot.self, from: before)
        let persistedBase = queue.world
        queue.world?.pendingWeatherEnabled = false
        expect(queue.effectiveWorld(at: now).weather == .snow && queue.pendingWeatherEffect(at: now).reason == nil,
               "turning off automatic weather immediately restores the saved choice")
        queue.world = persistedBase
        queue.isOnline = false; queue.updatedAt = now.addingTimeInterval(-5000)
        expect(queue.effectiveWorld(at: now).weather == .thunderstorm, "offline heartbeat does not reset pending age")
        queue = snapshot(age: -3600)
        expect(queue.pendingWeatherEffect(at: now).oldestWait == 0 && queue.effectiveWorld(at: now).weather == .snow,
               "future note dates clamp to zero")
        queue.pendingNotes = [PendingNote(text: "invalid", createdAt: Date(timeIntervalSince1970: .nan))]
        expect(queue.pendingWeatherEffect(at: now).stage == .none, "invalid in-memory note date cannot trigger a storm")
        expect(snapshot(age: 30_000).pendingWeatherEffect(at: Date(timeIntervalSince1970: .nan)).stage == .none,
               "invalid supplied clock resolves safely")
        queue = snapshot(age: 0)
        queue.tasks = [WorkplaceTask(id: "codex-running", title: "真实长任务", status: .running, slot: 0,
                                    startedAt: now.addingTimeInterval(-604800)),
                       WorkplaceTask(id: "approval", title: "等待确认", status: .waiting, slot: 1)]
        expect(queue.pendingWeatherEffect(at: now).stage == .none, "running Codex or approval state does not count as pending notes")
        let encoded = try JSONEncoder().encode(queue)
        _ = queue.effectiveWorld(at: now.addingTimeInterval(20_000))
        let unchanged = try JSONDecoder().decode(SceneSnapshot.self, from: encoded)
        expect(unchanged == queue,
               "weather resolution has no mutation or persistence side effects")
        let observerCopy = queue
        expect(queue.pendingWeatherEffect(at: now.addingTimeInterval(20_000))
               == observerCopy.pendingWeatherEffect(at: now.addingTimeInterval(20_000)), "independent hosts share one absolute-time rule")
        print("PASS: \(checks) pending-weather policy, boundary, compatibility and restoration checks")
    }
}
