enum RainDensity: String, CaseIterable {
    case low
    case medium
    case high

    var columnMultiplier: Float {
        switch self {
        case .low:
            return 0.8
        case .medium:
            return 1
        case .high:
            return 1.2
        }
    }
}

struct AppSettings: Equatable {
    var launchAtLogin = false
    var pauseWhenAllScreensAreFullscreen = true
    var pauseWhenOnBattery = false
    var showsDigitalClock = true
    var rainDensity: RainDensity = .medium
}
