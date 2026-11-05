import AppKit

@main
enum PendingWeatherIntegrationTests {
    static var checks = 0
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    static func scene(age: TimeInterval) -> SceneSnapshot {
        var value = SceneSnapshot.empty(now: now)
        value.mode = .sitting
        value.world = SceneWorld(weather: .clear, timeMode: .day)
        value.pendingNotes = [PendingNote(id: "weather-note", text: "等待交办的需求", createdAt: now.addingTimeInterval(-age), slot: 0)]
        return value
    }
    static func render(_ value: SceneSnapshot, background: WorkplaceBackground = .outdoors,
                       uptime: TimeInterval = 9) -> CGContext {
        let context = CGContext(data: nil, width: 1672, height: 941, bitsPerComponent: 8,
            bytesPerRow: 1672 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        SceneRenderer.draw(in: context, bounds: CGRect(x: 0, y: 0, width: 1672, height: 941),
            snapshot: value, time: uptime, reduceMotion: true, now: now, background: background)
        return context
    }
    static func identical(_ a: CGContext, _ b: CGContext, rect: CGRect? = nil) -> Bool {
        let region = rect ?? CGRect(x: 0, y: 0, width: a.width, height: a.height)
        for y in Int(region.minY)..<Int(region.maxY) {
            let offset = (a.height - 1 - y) * a.bytesPerRow + Int(region.minX) * 4
            if memcmp(a.data!.advanced(by: offset), b.data!.advanced(by: offset), Int(region.width) * 4) != 0 { return false }
        }
        return true
    }
    static func main() {
        _ = NSApplication.shared
        for (age, weather) in [(0.0, WorldWeather.clear), (3599, .clear), (3600, .cloudy),
                               (8999, .cloudy), (9000, .rain), (14399, .rain), (14400, .thunderstorm)] {
            let auto = scene(age: age)
            var manual = auto
            manual.world?.pendingWeatherEnabled = false
            manual.world?.weather = weather
            expect(identical(render(auto), render(manual)), "production renderer resolves correct weather at \(age)s")
            expect(auto.world?.weather == .clear, "rendering never overwrites the saved base weather")
        }
        var overdue = scene(age: 20_000)
        let storm = render(overdue)
        expect(identical(storm, render(overdue, uptime: 900_000)), "independent host uptime cannot change derived weather")
        overdue.isOnline = false
        overdue.updatedAt = now.addingTimeInterval(-60)
        expect(identical(storm, render(overdue)), "an offline companion does not discard outdoor pending weather")
        var roomStorm = scene(age: 20_000)
        var roomClear = roomStorm
        roomClear.world?.pendingWeatherEnabled = false
        let stormImage = render(roomStorm, background: .room)
        let clearImage = render(roomClear, background: .room)
        expect(!identical(stormImage, clearImage), "room windows and atmosphere respond to overdue notes")
        expect(identical(stormImage, clearImage, rect: CGRect(x: 690, y: 555, width: 245, height: 147)),
               "weather keeps live monitor information unchanged")
        roomStorm.pendingNotes = []
        roomClear.pendingNotes = []
        expect(identical(render(roomStorm), render(roomClear)), "handoff restores base weather with no sticky storm")
        roomStorm.pendingNotes = [PendingNote(id: "young-note", text: "新待办", createdAt: now.addingTimeInterval(-60), slot: 1)]
        roomClear.pendingNotes = roomStorm.pendingNotes
        expect(identical(render(roomStorm), render(roomClear)), "removing the oldest note leaves a young queue clear")
        let before = scene(age: 20_000)
        _ = render(before)
        expect(before.tasks.isEmpty && before.completedToday == 0 && before.world?.pendingWeatherPace == .balanced,
               "weather does not create tasks, increment completed count or change the selected schedule")
        print("PASS: \(checks) pending-weather production renderer integration checks")
    }
}
