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

extension SceneSnapshot {
    /// Derived solely from durable personal notes and the supplied absolute
    /// clock. Task status, host uptime and freshness never reset the wait.
    func pendingWeatherEffect(at now: Date) -> PendingWeatherEffect {
        let base = world ?? SceneWorld()
        guard now.timeIntervalSince1970.isFinite,
              let oldest = pendingNotes?.filter({
                  $0.createdAt.timeIntervalSince1970.isFinite && $0.createdAt.timeIntervalSince1970 >= 0
              }).min(by: { $0.createdAt < $1.createdAt }) else {
            return PendingWeatherEffect(stage:.none,oldestWait:0,weather:base.weather,reason:nil)
        }
        let elapsed = max(0, now.timeIntervalSince(oldest.createdAt))
        let wait = elapsed.isFinite ? elapsed : 0
        guard base.pendingWeatherEnabled else {
            return PendingWeatherEffect(stage:.none,oldestWait:wait,weather:base.weather,reason:nil)
        }
        let stage: PendingWeatherStage
        let weather: WorldWeather
        if wait >= base.pendingWeatherPace.stormAfter {
            stage = .thunderstorm; weather = .thunderstorm
        } else if wait >= base.pendingWeatherPace.rainAfter {
            stage = .rain; weather = .rain
        } else if wait >= base.pendingWeatherPace.cloudyAfter {
            stage = .cloudy; weather = .cloudy
        } else {
            return PendingWeatherEffect(stage:.none,oldestWait:wait,weather:base.weather,reason:nil)
        }
        return PendingWeatherEffect(stage:stage,oldestWait:wait,weather:weather,
            reason:"最早的门外待办\(oldest.waitingLabel(at:now))，天气转为\(weather.title)")
    }

    /// The manual weather remains stored in `world`; removing notes or
    /// disabling their effect restores it without writing preference changes.
    func effectiveWorld(at now: Date) -> SceneWorld {
        var result = world ?? SceneWorld()
        result.weather = pendingWeatherEffect(at:now).weather
        return result
    }
}
