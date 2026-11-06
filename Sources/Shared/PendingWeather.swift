import Foundation

enum PendingWeatherPace: String, Codable, CaseIterable {
    case quick, balanced, relaxed

    var title: String {
        switch self {
        case .quick: return "快速"
        case .balanced: return "均衡"
        case .relaxed: return "宽松"
        }
    }

    var cloudyAfter: TimeInterval {
        switch self {
        case .quick: return 30 * 60
        case .balanced: return 60 * 60
        case .relaxed: return 4 * 60 * 60
        }
    }

    var stormAfter: TimeInterval {
        switch self {
        case .quick: return 2 * 60 * 60
        case .balanced: return 4 * 60 * 60
        case .relaxed: return 24 * 60 * 60
        }
    }

    var rainAfter: TimeInterval { cloudyAfter + (stormAfter - cloudyAfter) / 2 }
}

enum PendingWeatherStage: String, Codable, CaseIterable {
    case none, cloudy, rain, thunderstorm
}

struct PendingWeatherEffect: Equatable {
    var stage: PendingWeatherStage
    var oldestWait: TimeInterval
    var weather: WorldWeather
    var reason: String?
}

/// A shared pseudorandom weather calendar. Absolute 45-minute periods, rather
/// than a per-process random generator or timer, keep every display and saver
/// in sync across restarts and while the companion application is offline.
enum RandomWeatherPolicy {
    static let interval: TimeInterval = 45 * 60

    private static func bucket(at date: Date) -> UInt64? {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let period = floor(seconds / interval)
        guard period < Double(UInt64.max) else { return nil }
        return UInt64(period)
    }

    static func weather(at date: Date) -> WorldWeather {
        guard let period = bucket(at: date) else { return .clear }
        // SplitMix64 with an authored salt; Swift Hasher is randomized per
        // process and therefore cannot define a cross-process weather calendar.
        var value = period &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        let choice = (value ^ (value >> 31)) % 100
        switch choice {
        case 0..<65: return .clear
        case 65..<83: return .cloudy
        case 83..<93: return .rain
        case 93..<98: return .snow
        default: return .thunderstorm
        }
    }

    static func nextChange(after date: Date) -> Date? {
        guard let period = bucket(at: date), period < UInt64.max else { return nil }
        let seconds = Double(period + 1) * interval
        guard seconds.isFinite, seconds > date.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension SceneSnapshot {
    /// Compatibility for old diagnostic callers. Pending notes deliberately
    /// have no weather stage or explanation under the independent policy.
    func pendingWeatherEffect(at now: Date) -> PendingWeatherEffect {
        PendingWeatherEffect(stage: .none, oldestWait: 0,
            weather: effectiveWorld(at: now).weather, reason: nil)
    }

    /// Resolution is read-only: never overwrite the saved fixed-weather choice.
    func effectiveWorld(at now: Date) -> SceneWorld {
        var result = world ?? SceneWorld()
        if result.weatherMode == .random { result.weather = RandomWeatherPolicy.weather(at: now) }
        return result
    }
}
