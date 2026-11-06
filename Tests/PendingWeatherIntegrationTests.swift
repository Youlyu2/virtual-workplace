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
                       at date: Date = now, uptime: TimeInterval = 9) -> CGContext {
        let context = CGContext(data: nil, width: 1672, height: 941, bitsPerComponent: 8,
            bytesPerRow: 1672 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        SceneRenderer.draw(in: context, bounds: CGRect(x: 0, y: 0, width: 1672, height: 941),
            snapshot: value, time: uptime, reduceMotion: true, now: date, background: background)
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
        for offset in [0.0, 2699, 2700, 5400, 27_000, 270_000] {
            let date = now.addingTimeInterval(offset)
            let random = scene(age: 200_000)
            var manual = random
            manual.world?.weatherMode = .manual
            manual.world?.weather = RandomWeatherPolicy.weather(at: date)
            expect(identical(render(random, at: date), render(manual, at: date)),
                   "production renderer resolves shared random weather at \(offset)s")
            expect(random.world?.weather == .clear && random.world?.weatherMode == .random,
                   "rendering never overwrites the saved manual choice or random mode")
        }
        var overdue = scene(age: 200_000)
        let sky = CGRect(x: 0, y: 500, width: 1672, height: 441)
        let randomImage = render(overdue)
        expect(identical(randomImage, render(overdue, uptime: 900_000)),
               "independent host uptime cannot change random weather")
        overdue.isOnline = false
        overdue.updatedAt = now.addingTimeInterval(-60)
        expect(identical(randomImage, render(overdue), rect: sky),
               "offline companion keeps the same shared outdoor weather")
        var young = scene(age: 60)
        expect(identical(randomImage, render(young), rect: sky),
               "note age never changes the landscape weather")
        let beforeHandoff = render(young, background: .room)
        young.pendingNotes = []
        expect(identical(beforeHandoff, render(young, background: .room)),
               "handing off the last note does not change room window weather")
        var storm = scene(age: 200_000)
        storm.world?.weatherMode = .manual
        storm.world?.weather = .thunderstorm
        var clear = storm
        clear.world?.weather = .clear
        let stormImage = render(storm, background: .room)
        let clearImage = render(clear, background: .room)
        expect(!identical(stormImage, clearImage), "manual room weather remains selectable")
        expect(identical(stormImage, clearImage, rect: CGRect(x: 690, y: 555, width: 245, height: 147)),
               "weather keeps live monitor information unchanged")
        storm.pendingNotes = []
        expect(storm.effectiveWorld(at: now).weather == .thunderstorm,
               "manual choice persists after the inbox clears")
        let before = scene(age: 200_000)
        _ = render(before)
        expect(before.tasks.isEmpty && before.completedToday == 0 && before.world?.weatherMode == .random,
               "weather does not create tasks, increment completed count or change mode")
        print("PASS: \(checks) random-weather production renderer integration checks")
    }
}
