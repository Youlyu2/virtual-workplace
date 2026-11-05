import Foundation

@main
enum WorldSettingsTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    private static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); fatalError("FAIL: expected rejection: \(message)") }
        catch { checks += 1 }
    }

    static func main() throws {
        // No live preferences, display configuration, task observer or UI used.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 2,
                                               hour: hour, minute: minute, second: second))!
        }
        let world = SceneWorld()
        expect(world.weather == .clear && world.timeMode == .automatic && world.displayScenes.isEmpty
               && world.screenSaverDisplayScenes.isEmpty,
               "new preferences have a clear local-time world and independent empty display assignments")
        let legacyData = Data("{\"weather\":\"rain\",\"timeMode\":\"sunset\",\"displayScenes\":{\"legacy-display\":\"outdoors\"}}".utf8)
        let legacy = try JSONDecoder().decode(SceneWorld.self, from: legacyData)
        expect(legacy.displayScenes == ["legacy-display": .outdoors] && legacy.screenSaverDisplayScenes.isEmpty
               && legacy.weather == .rain && legacy.timeMode == .sunset,
               "legacy files retain desktop choices without copying them into saver preferences")
        let migrated = try JSONDecoder().decode(SceneWorld.self, from: JSONEncoder().encode(legacy))
        expect(migrated == legacy, "legacy preference migration is lossless on its next save")
        expect(SceneDisplayContext.allCases.map(\.title) == ["桌面背景", "系统屏保"],
               "display contexts have stable separate labels")
        let midnight = world.environment(at: date(0), calendar: calendar)
        let six = world.environment(at: date(6), calendar: calendar)
        let seven = world.environment(at: date(7), calendar: calendar)
        let eight = world.environment(at: date(8), calendar: calendar)
        let noon = world.environment(at: date(12), calendar: calendar)
        let five = world.environment(at: date(17), calendar: calendar)
        let dusk = world.environment(at: date(18, 30), calendar: calendar)
        let night = world.environment(at: date(20), calendar: calendar)
        expect(midnight.daylight == 0 && midnight.darkness == 1 && midnight.title == "夜晚",
               "midnight is night rather than a view-relative elapsed phase")
        expect(six.daylight == 0 && six.darkness == 1 && six.title == "清晨", "dawn starts at06 without a lighting jump")
        expect(seven.daylight == 0.5 && seven.darkness == 0.5 && seven.sunset > 0,
               "dawn transitions smoothly through half daylight")
        expect(eight.daylight == 1 && noon.daylight == 1 && eight.darkness == 0,
               "daytime reaches and keeps full daylight")
        expect(five.daylight == 1 && five.sunset == 0 && five.title == "黄昏",
               "sunset starts continuously from daytime")
        expect(abs(dusk.daylight - 0.5) < 0.00001 && abs(dusk.sunset - 1) < 0.00001,
               "sunset reaches warm half-light at18:30")
        expect(night.daylight == 0 && night.darkness == 1 && night.sunset == 0,
               "night starts at20 with no leftover sunset overlay")
        let beforeDawn = world.environment(at: date(5, 59, 59), calendar: calendar)
        let afterDawn = world.environment(at: date(6, 0, 1), calendar: calendar)
        let beforeDay = world.environment(at: date(7, 59, 59), calendar: calendar)
        let afterDay = world.environment(at: date(8, 0, 1), calendar: calendar)
        let beforeNight = world.environment(at: date(19, 59, 59), calendar: calendar)
        let afterNight = world.environment(at: date(20, 0, 1), calendar: calendar)
        expect(abs(beforeDawn.daylight - afterDawn.daylight) < 0.00001
               && abs(beforeDay.daylight - afterDay.daylight) < 0.00001
               && abs(beforeNight.daylight - afterNight.daylight) < 0.00001,
               "lighting stays continuous across phase boundaries")
        let samples = (0..<96).map { world.environment(at: date($0 / 4, ($0 % 4) * 15), calendar: calendar) }
        expect(samples.allSatisfy {
            $0.daylight.isFinite && $0.sunset.isFinite && $0.darkness.isFinite
                && (0...1).contains($0.daylight) && (0...1).contains($0.sunset) && (0...1).contains($0.darkness)
                && abs($0.daylight + $0.darkness - 1) < 0.00001
        }, "all daily lighting samples stay finite, complementary and bounded")
        expect((6..<8).allSatisfy { hour in
            world.environment(at: date(hour), calendar: calendar).daylight
                < world.environment(at: date(hour + 1), calendar: calendar).daylight
        }, "dawn brightness only increases")
        expect((17..<20).allSatisfy { hour in
            world.environment(at: date(hour), calendar: calendar).daylight
                > world.environment(at: date(hour + 1), calendar: calendar).daylight
        }, "sunset brightness only decreases")
        let secondView = world
        expect(world.environment(at: date(18, 10, 32), calendar: calendar)
               == secondView.environment(at: date(18, 10, 32), calendar: calendar),
               "independent hosts given the same date get exactly the same world")
        expect(SceneWorld(weather: .rain).environment(at: date(18, 10), calendar: calendar)
               == SceneWorld(weather: .snow).environment(at: date(18, 10), calendar: calendar),
               "weather choice does not restart or skew the lighting clock")
        for mode in [WorldTimeMode.day, .sunset, .night] {
            let fixed = SceneWorld(timeMode: mode)
            expect(fixed.environment(at: date(1), calendar: calendar) == fixed.environment(at: date(13), calendar: calendar),
                   "\(mode) preview is stable at any real time")
        }
        expect(SceneWorld(timeMode: .day).environment(at: date(1), calendar: calendar).daylight == 1
               && SceneWorld(timeMode: .night).environment(at: date(13), calendar: calendar).darkness == 1,
               "day and night overrides are independent of the clock")
        var losAngeles = calendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        expect(world.environment(at: date(18), calendar: calendar).title == "黄昏"
               && world.environment(at: date(18), calendar: losAngeles).title == "白天",
               "automatic mode follows the device calendar rather than UTC")
        let fallback = world.environment(at: Date(timeIntervalSinceReferenceDate: .infinity), calendar: calendar)
        expect(fallback.daylight.isFinite && fallback.darkness.isFinite,
               "invalid diagnostic dates cannot produce nonfinite lighting")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Workplace-world-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = WorldSettingsStore(url: directory.appendingPathComponent("preferences/world-settings.json"))
        rejects("missing preferences") { _ = try preferences.read() }
        let chosen = SceneWorld(weather: .rain, timeMode: .sunset,
            displayScenes: ["left-display-uuid": .outdoors, "main-display-uuid": .room],
            screenSaverDisplayScenes: ["left-display-uuid": .room, "main-display-uuid": .outdoors])
        try preferences.write(chosen)
        let firstLoad = try preferences.read()
        expect(firstLoad == chosen, "all display scenes and shared environment survive atomic persistence")
        let restarted = WorldSettingsStore(url: preferences.url)
        let restartLoad = try restarted.read()
        expect(restartLoad == chosen, "new store instance restores preferences after app restart")
        var swapped = chosen
        swapped.displayScenes["left-display-uuid"] = .room
        swapped.displayScenes["main-display-uuid"] = .outdoors
        try restarted.write(swapped)
        let swappedLoad = try preferences.read()
        expect(swappedLoad == swapped, "each display can be reassigned independently")
        expect(swappedLoad.screenSaverDisplayScenes == chosen.screenSaverDisplayScenes,
               "desktop changes preserve the separately saved saver backgrounds")
        var viaHelpers = chosen
        viaHelpers.setDisplayScenes(["new-desktop": .room], for: .desktop)
        expect(viaHelpers.displayScenes(for: .desktop) == ["new-desktop": .room]
               && viaHelpers.displayScenes(for: .screenSaver) == chosen.screenSaverDisplayScenes,
               "desktop map helpers update only the requested context")
        viaHelpers.setDisplayScenes(["new-saver": .outdoors], for: .screenSaver)
        expect(viaHelpers.displayScenes == ["new-desktop": .room]
               && viaHelpers.screenSaverDisplayScenes == ["new-saver": .outdoors]
               && viaHelpers.weather == chosen.weather && viaHelpers.timeMode == chosen.timeMode,
               "saver map helpers preserve desktop selections and the common environment")
        var tooMany = chosen
        tooMany.displayScenes = Dictionary(uniqueKeysWithValues: (0..<33).map { ("display-\($0)", .room) })
        rejects("more than32 displays") { try preferences.write(tooMany) }
        let afterInvalidWrite = try preferences.read()
        expect(afterInvalidWrite == swapped, "invalid preferences cannot replace the last valid file")
        var maxDisplays = tooMany
        maxDisplays.displayScenes.removeValue(forKey: "display-32")
        maxDisplays.screenSaverDisplayScenes = maxDisplays.displayScenes
        try WorldSettingsStore.validate(maxDisplays)
        expect(maxDisplays.displayScenes.count == 32 && maxDisplays.screenSaverDisplayScenes.count == 32,
               "each context independently accepts32 display entries")
        var tooManySaver = chosen
        tooManySaver.screenSaverDisplayScenes = tooMany.displayScenes
        rejects("more than32 saver displays") { try preferences.write(tooManySaver) }
        let afterInvalidSaverWrite = try preferences.read()
        expect(afterInvalidSaverWrite == swapped, "invalid saver preferences cannot replace the last valid file")
        for key in ["", " padded", "line\nbreak", String(repeating: "x", count: 129), String(repeating: "屏", count: 43)] {
            rejects("invalid display identity") { try WorldSettingsStore.validate(SceneWorld(displayScenes: [key: .room])) }
            rejects("invalid saver display identity") {
                try WorldSettingsStore.validate(SceneWorld(screenSaverDisplayScenes: [key: .outdoors]))
            }
        }
        try WorldSettingsStore.validate(SceneWorld(displayScenes: [String(repeating: "x", count: 128): .room]))
        try WorldSettingsStore.validate(SceneWorld(screenSaverDisplayScenes: [String(repeating: "x", count: 128): .room]))
        expect(true, "128-byte display identity is accepted")
        rejects("corrupt preferences") {
            try Data("{bad json".utf8).write(to: preferences.url)
            _ = try preferences.read()
        }
        rejects("oversized preferences") {
            try Data(repeating: 32, count: 32_769).write(to: preferences.url)
            _ = try preferences.read()
        }
        rejects("unknown weather enum") { _ = try JSONDecoder().decode(SceneWorld.self, from: Data("{\"weather\":\"hurricane\"}".utf8)) }
        rejects("unknown saver background enum") {
            _ = try JSONDecoder().decode(SceneWorld.self, from: Data("{\"screenSaverDisplayScenes\":{\"display\":\"forest\"}}".utf8))
        }
        let minimal = try JSONDecoder().decode(SceneWorld.self, from: Data("{}".utf8))
        expect(minimal == SceneWorld(), "missing optional preference fields use safe defaults")
        var lastValid = chosen
        if let loaded = try? preferences.read() { lastValid = loaded }
        expect(lastValid == chosen, "read failures let the owner retain the previous valid world")

        let stateStore = StateStore(url: directory.appendingPathComponent("state.json"))
        var snapshot = SceneSnapshot.empty(now: date(12))
        snapshot.tasks = [WorkplaceTask(id: "existing", title: "Existing real task", status: .running, slot: 0)]
        snapshot.world = chosen
        try stateStore.write(snapshot)
        let saverSnapshot = try stateStore.read()
        expect(saverSnapshot.world == chosen && saverSnapshot.tasks == snapshot.tasks,
               "app-to-saver snapshot shares environment without rewriting tasks")
        expect(saverSnapshot.world?.environment(at: date(18, 15), calendar: calendar)
               == snapshot.world?.environment(at: date(18, 15), calendar: calendar),
               "saver restores the same lighting decisions as the companion app")
        var legacySnapshotJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: stateStore.url)) as! [String: Any]
        var legacyWorldJSON = legacySnapshotJSON["world"] as! [String: Any]
        legacyWorldJSON.removeValue(forKey: "screenSaverDisplayScenes")
        legacySnapshotJSON["world"] = legacyWorldJSON
        try JSONSerialization.data(withJSONObject: legacySnapshotJSON).write(to: stateStore.url)
        let oldWorldSnapshot = try stateStore.read()
        expect(oldWorldSnapshot.world?.displayScenes == chosen.displayScenes
               && oldWorldSnapshot.world?.screenSaverDisplayScenes.isEmpty == true
               && oldWorldSnapshot.tasks == snapshot.tasks,
               "legacy shared snapshots preserve tasks and desktop choices without populating saver choices")
        snapshot.world = tooMany
        rejects("invalid world in shared state") { try stateStore.write(snapshot) }
        snapshot.world = tooManySaver
        rejects("invalid saver world in shared state") { try stateStore.write(snapshot) }
        snapshot.world = nil
        try stateStore.write(snapshot)
        let oldData = try Data(contentsOf: stateStore.url)
        let oldJSON = try JSONSerialization.jsonObject(with: oldData) as! [String: Any]
        let oldSnapshot = try stateStore.read()
        expect(oldJSON["world"] == nil && oldSnapshot.world == nil,
               "older snapshots without world settings remain compatible")
        print("PASS: \(checks) shared world clock, preferences, display mapping and compatibility checks (isolated files only)")
    }
}
