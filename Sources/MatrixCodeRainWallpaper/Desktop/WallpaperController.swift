import AppKit

final class WallpaperController: NSObject {
    private var windows: [WallpaperWindow] = []
    private var fullscreenCheckTimer: Timer?
    private var fullscreenDebounceTimer: Timer?
    private var fullscreenNotificationObservers: [NSObjectProtocol] = []
    private var powerCheckTimer: Timer?
    private var powerObservation: PowerSourceMonitor.Observation?
    private var powerCheckInFlight = false
    private var appliedPauseState: Bool?
    private var appliedWallpaperHiddenState: Bool?
    private(set) var settings = SettingsStore.load()
    private(set) var isManuallyPaused = false
    private(set) var isPausedForFullscreen = false
    private(set) var isPausedForPower = false

    var isEffectivelyPaused: Bool {
        isManuallyPaused || isPausedForFullscreen || isPausedForPower
    }

    func start() {
        synchronizeLaunchAtLoginState()
        configureFullscreenMonitoring()
        configurePowerMonitoring()
        updateFullscreenPauseState()
        updatePowerPauseState()
        rebuildWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        fullscreenCheckTimer?.invalidate()
        fullscreenCheckTimer = nil
        fullscreenDebounceTimer?.invalidate()
        fullscreenDebounceTimer = nil
        removeFullscreenNotificationObservers()
        powerCheckTimer?.invalidate()
        powerCheckTimer = nil
        powerObservation?.invalidate()
        powerObservation = nil
        NotificationCenter.default.removeObserver(self)
        closeWindows()
    }

    @discardableResult
    func togglePause() -> Bool {
        isManuallyPaused ? resume() : pause()
        return isManuallyPaused
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        SettingsStore.save(settings)
        configureFullscreenMonitoring()
        configurePowerMonitoring()
        updateFullscreenPauseState()
        updatePowerPauseState()
        applyPauseState()
    }

    private func pause() {
        isManuallyPaused = true
        applyPauseState()
    }

    private func resume() {
        isManuallyPaused = false
        applyPauseState()
    }

    func rebuildWindows() {
        closeWindows()
        windows = NSScreen.screens.map { screen in
            let window = WallpaperWindow(screen: screen, isPaused: isEffectivelyPaused)
            return window
        }
        applyPauseState()
    }

    private func closeWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
        appliedPauseState = nil
        appliedWallpaperHiddenState = nil
    }

    private func configureFullscreenMonitoring() {
        fullscreenCheckTimer?.invalidate()
        fullscreenCheckTimer = nil
        fullscreenDebounceTimer?.invalidate()
        fullscreenDebounceTimer = nil
        removeFullscreenNotificationObservers()

        guard settings.pauseWhenAllScreensAreFullscreen else {
            isPausedForFullscreen = false
            return
        }

        installFullscreenNotificationObservers()

        let timer = Timer(
            timeInterval: 8,
            target: self,
            selector: #selector(fullscreenStateMayHaveChanged),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        fullscreenCheckTimer = timer
    }

    private func installFullscreenNotificationObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]

        fullscreenNotificationObservers = notifications.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleFullscreenStateUpdate()
            }
        }
    }

    private func removeFullscreenNotificationObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        fullscreenNotificationObservers.forEach { workspaceCenter.removeObserver($0) }
        fullscreenNotificationObservers.removeAll()
    }

    private func scheduleFullscreenStateUpdate() {
        guard settings.pauseWhenAllScreensAreFullscreen else {
            return
        }

        fullscreenDebounceTimer?.invalidate()

        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(fullscreenDebounceTimerFired),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        fullscreenDebounceTimer = timer
    }

    private func configurePowerMonitoring() {
        powerCheckTimer?.invalidate()
        powerCheckTimer = nil
        powerObservation?.invalidate()
        powerObservation = nil
        powerCheckInFlight = false

        guard settings.pauseWhenOnBattery else {
            isPausedForPower = false
            return
        }

        powerObservation = PowerSourceMonitor.observeChanges { [weak self] in
            DispatchQueue.main.async {
                self?.updatePowerPauseState()
            }
        }

        let timer = Timer(
            timeInterval: powerObservation == nil ? 5 : 60,
            target: self,
            selector: #selector(powerStateMayHaveChanged),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = powerObservation == nil ? 1 : 10
        RunLoop.main.add(timer, forMode: .common)
        powerCheckTimer = timer
    }

    private func updateFullscreenPauseState() {
        guard settings.pauseWhenAllScreensAreFullscreen else {
            isPausedForFullscreen = false
            applyPauseState()
            return
        }

        isPausedForFullscreen = FullscreenCoverageMonitor.areAllScreensCoveredByFullscreenWindows()
        applyPauseState()
    }

    private func updatePowerPauseState() {
        guard settings.pauseWhenOnBattery else {
            isPausedForPower = false
            applyPauseState()
            return
        }

        guard !powerCheckInFlight else {
            return
        }

        powerCheckInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let isConnected = PowerSourceMonitor.isPowerAdapterConnected

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.powerCheckInFlight = false
                self.isPausedForPower = self.settings.pauseWhenOnBattery && !isConnected
                self.applyPauseState()
            }
        }
    }

    private func applyPauseState() {
        let shouldPause = isEffectivelyPaused
        let shouldHideWallpaper = isPausedForPower

        if appliedPauseState != shouldPause {
            if shouldPause {
                windows.forEach { $0.pauseAnimation() }
            } else {
                windows.forEach { $0.resumeAnimation() }
            }

            appliedPauseState = shouldPause
        }

        if appliedWallpaperHiddenState != shouldHideWallpaper {
            if shouldHideWallpaper {
                windows.forEach { $0.hideWallpaper() }
            } else {
                windows.forEach { $0.showWallpaper() }
            }

            appliedWallpaperHiddenState = shouldHideWallpaper
        }
    }

    private func synchronizeLaunchAtLoginState() {
        guard settings.launchAtLogin else {
            return
        }

        try? LoginItemManager.setEnabled(true)
    }

    @objc private func fullscreenStateMayHaveChanged() {
        updateFullscreenPauseState()
    }

    @objc private func fullscreenDebounceTimerFired() {
        fullscreenDebounceTimer = nil
        updateFullscreenPauseState()
    }

    @objc private func powerStateMayHaveChanged() {
        updatePowerPauseState()
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        rebuildWindows()
        updateFullscreenPauseState()
    }
}
