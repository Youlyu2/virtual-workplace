import Foundation

@main
enum PendingWeatherTests {
    private static var checks = 0
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    private static func snapshot(age: TimeInterval) -> SceneSnapshot {
        var result = SceneSnapshot.empty(now: now)
        result.world = SceneWorld(weather: .snow, timeMode: .night)
        result.pendingNotes = [PendingNote(id: "oldest", text: "等候交办", createdAt: now.addingTimeInterval(-age), slot: 0)]
        return result
    }

    static func main() throws {
        expect(SceneWorld().weatherMode == .random, "new worlds default to independent random weather")
        expect(RandomWeatherPolicy.interval == 2700, "weather changes are evaluated in45-minute periods")
        // These fixed dates pin the shared calendar across processes/releases;
        // a process-randomized Swift Hasher would not satisfy these vectors.
        let vectors: [(TimeInterval, WorldWeather)] = [(0, .clear), (2699, .clear), (2700, .cloudy),
            (5400, .clear), (86400, .clear), (1_800_000_000, .clear)]
        for (seconds, weather) in vectors {
            expect(RandomWeatherPolicy.weather(at: Date(timeIntervalSince1970: seconds)) == weather,
                   "the stable calendar matches the published fixture at\(seconds)")
        }
        for period in 0..<128 {
            let start = Double(period) * RandomWeatherPolicy.interval
            let a = Date(timeIntervalSince1970: start)
            let end = Date(timeIntervalSince1970: start + RandomWeatherPolicy.interval - 0.001)
            let boundary = Date(timeIntervalSince1970: start + RandomWeatherPolicy.interval)
            expect(RandomWeatherPolicy.weather(at: a) == RandomWeatherPolicy.weather(at: end),
                   "weather remains constant through period\(period)")
            expect(RandomWeatherPolicy.nextChange(after: a) == boundary
                   && RandomWeatherPolicy.nextChange(after: end) == boundary,
                   "next evaluation is exactly the shared period boundary")
            expect(RandomWeatherPolicy.nextChange(after: boundary)
                   == boundary.addingTimeInterval(RandomWeatherPolicy.interval),
                   "a boundary itself belongs to the next period")
        }
        var counts: [WorldWeather: Int] = [:]
        for period in 0..<10_000 {
            counts[RandomWeatherPolicy.weather(at: Date(timeIntervalSince1970: Double(period) * 2700)), default: 0] += 1
        }
        let bands: [(WorldWeather, ClosedRange<Int>)] = [(.clear, 6000...7000), (.cloudy, 1500...2100),
            (.rain, 800...1200), (.snow, 300...700), (.thunderstorm, 100...300)]
        for (weather, range) in bands {
            expect(range.contains(counts[weather, default: 0]), "\(weather) stays within its intended frequency band over10,000 periods")
        }
        expect(counts[.clear, default: 0] > 5000 && counts[.thunderstorm, default: 0] < counts[.rain, default: 0],
               "sunshine is the majority and thunderstorms remain uncommon")

        for enabled in [true, false] {
            let data = Data("{\"weather\":\"snow\",\"timeMode\":\"night\",\"pendingWeatherEnabled\":\(enabled),\"pendingWeatherPace\":\"relaxed\",\"displayScenes\":{\"left\":\"outdoors\"}}".utf8)
            let legacy = try JSONDecoder().decode(SceneWorld.self, from: data)
            expect(legacy.weatherMode == .random && legacy.weather == .snow && legacy.timeMode == .night
                   && legacy.displayScenes == ["left": .outdoors],
                   "old enabled or disabled pending policies migrate to random without losing other preferences")
            let migrated = try JSONDecoder().decode(SceneWorld.self, from: JSONEncoder().encode(legacy))
            expect(migrated == legacy,
                   "migrated preferences round-trip with an explicit mode")
        }
        var source = snapshot(age: 40 * 86400)
        let original = source
        let baseline = source.effectiveWorld(at: now)
        expect(baseline.weather == RandomWeatherPolicy.weather(at: now) && baseline.timeMode == .night
               && source.world?.weather == .snow, "resolving random weather preserves manual choice and daylight")
        for age in [TimeInterval(0), 3599, 3600, 9000, 14400, 4_000_000, -3600] {
            var queue = snapshot(age: age)
            queue.world?.pendingWeatherPace = .quick
            queue.world?.pendingWeatherEnabled = false
            expect(queue.effectiveWorld(at: now).weather == baseline.weather,
                   "note age\(age) and old policy fields cannot influence random weather")
            let effect = queue.pendingWeatherEffect(at: now)
            expect(effect.stage == .none && effect.reason == nil && effect.weather == baseline.weather,
                   "the compatibility projection never blames pending notes for weather")
        }
        source.pendingNotes?.append(PendingNote(id: "new", text: "刚记下的事", createdAt: now))
        source.pendingNotes?.reverse()
        expect(source.effectiveWorld(at: now).weather == baseline.weather, "note ordering and adding visitors do not change weather")
        source.pendingNotes = []
        expect(source.effectiveWorld(at: now).weather == baseline.weather, "emptying the inbox does not reset the weather calendar")
        source.pendingNotes = nil
        expect(source.effectiveWorld(at: now).weather == baseline.weather, "legacy snapshots without notes use the same calendar")
        source.pendingNotes = [PendingNote(text: "invalid", createdAt: Date(timeIntervalSince1970: .nan))]
        expect(source.effectiveWorld(at: now).weather == baseline.weather, "invalid note dates are unrelated to random weather")
        source.tasks = [WorkplaceTask(id: "long", title: "长任务", status: .running, slot: 0,
            startedAt: now.addingTimeInterval(-604800)), WorkplaceTask(id: "approval", title: "等待确认", status: .waiting, slot: 1)]
        source.isOnline = false; source.updatedAt = now.addingTimeInterval(-5000)
        expect(source.effectiveWorld(at: now).weather == baseline.weather, "task state, offline heartbeat and host uptime cannot change the calendar")

        for weather in WorldWeather.allCases {
            var fixed = original
            fixed.world?.weather = weather
            fixed.world?.weatherMode = .manual
            for date in [now, now.addingTimeInterval(2700), now.addingTimeInterval(30 * 86400)] {
                expect(fixed.effectiveWorld(at: date).weather == weather, "manual\(weather) persists across random periods and old notes")
            }
            fixed.pendingNotes = []
            expect(fixed.effectiveWorld(at: now).weather == weather, "manual weather survives emptying the inbox")
            fixed.world?.weatherMode = .random
            expect(fixed.effectiveWorld(at: now).weather == baseline.weather && fixed.world?.weather == weather,
                   "switching to random does not overwrite the saved manual choice")
            fixed.world?.weatherMode = .manual
            expect(fixed.effectiveWorld(at: now).weather == weather, "switching back restores the exact manual choice")
        }
        for seconds in [TimeInterval.nan, .infinity, -.infinity, -.greatestFiniteMagnitude, .greatestFiniteMagnitude, -1] {
            let date = Date(timeIntervalSince1970: seconds)
            expect(RandomWeatherPolicy.weather(at: date) == .clear && RandomWeatherPolicy.nextChange(after: date) == nil,
                   "invalid or unsupported clocks fall back safely without overflow")
        }
        var noWorld = SceneSnapshot.empty(now: now)
        noWorld.world = nil
        expect(noWorld.effectiveWorld(at: now).weather == baseline.weather, "missing world data receives the same safe random default")
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SceneSnapshot.self, from: encoded)
        for advance in [TimeInterval(0), 2700, 86400] {
            let date = now.addingTimeInterval(advance)
            expect(original.effectiveWorld(at: date) == restored.effectiveWorld(at: date),
                   "independent app and saver copies share weather after time advance\(advance)")
        }
        _ = original.effectiveWorld(at: now.addingTimeInterval(86400))
        expect(original == restored, "weather resolution never mutates notes, tasks or stored preferences")
        print("PASS: \(checks) independent random-weather calendar, frequency, migration and manual-choice checks")
    }
}
