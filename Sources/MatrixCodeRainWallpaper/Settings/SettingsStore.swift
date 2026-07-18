import Foundation

enum SettingsStore {
    private enum Key {
        static let launchAtLogin = "settings.launchAtLogin"
        static let pauseWhenAllScreensAreFullscreen = "settings.pauseWhenAllScreensAreFullscreen"
        static let pauseWhenOnBattery = "settings.pauseWhenOnBattery"
        static let showsDigitalClock = "settings.showsDigitalClock"
        static let rainDensity = "settings.rainDensity"
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        var settings = AppSettings()

        if defaults.object(forKey: Key.launchAtLogin) != nil {
            settings.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        }

        if defaults.object(forKey: Key.pauseWhenAllScreensAreFullscreen) != nil {
            settings.pauseWhenAllScreensAreFullscreen = defaults.bool(
                forKey: Key.pauseWhenAllScreensAreFullscreen
            )
        }

        if defaults.object(forKey: Key.pauseWhenOnBattery) != nil {
            settings.pauseWhenOnBattery = defaults.bool(forKey: Key.pauseWhenOnBattery)
        }

        if defaults.object(forKey: Key.showsDigitalClock) != nil {
            settings.showsDigitalClock = defaults.bool(forKey: Key.showsDigitalClock)
        }

        if let rawDensity = defaults.string(forKey: Key.rainDensity),
           let density = RainDensity(rawValue: rawDensity) {
            settings.rainDensity = density
        }

        return settings
    }

    static func save(_ settings: AppSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(
            settings.pauseWhenAllScreensAreFullscreen,
            forKey: Key.pauseWhenAllScreensAreFullscreen
        )
        defaults.set(settings.pauseWhenOnBattery, forKey: Key.pauseWhenOnBattery)
        defaults.set(settings.showsDigitalClock, forKey: Key.showsDigitalClock)
        defaults.set(settings.rainDensity.rawValue, forKey: Key.rainDensity)
    }
}
