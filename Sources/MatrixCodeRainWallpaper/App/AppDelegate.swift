import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let appDisplayName = "Matrix code rain wallpaper"
    private static let authorCredit = "by Algernon"

    private let wallpaperController = WallpaperController()
    private var statusItem: NSStatusItem?
    private let appNameItem = NSMenuItem(
        title: AppDelegate.appDisplayName,
        action: nil,
        keyEquivalent: ""
    )
    private let authorItem = NSMenuItem(
        title: AppDelegate.authorCredit,
        action: nil,
        keyEquivalent: ""
    )
    private let pauseResumeItem = NSMenuItem(
        title: "暂停 / Pause",
        action: #selector(togglePause),
        keyEquivalent: ""
    )
    private let launchAtLoginItem = NSMenuItem(
        title: "开机自启动 / Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private let pauseWhenFullscreenItem = NSMenuItem(
        title: "全屏自动暂停 / Pause in Full Screen",
        action: #selector(togglePauseWhenFullscreen),
        keyEquivalent: ""
    )
    private let pauseWhenOnBatteryItem = NSMenuItem(
        title: "离电自动暂停 / Pause on Battery",
        action: #selector(togglePauseWhenOnBattery),
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        wallpaperController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperController.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.title = ""
            button.image = StatusBarIcon.makeLogoIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "\(Self.appDisplayName)\n\(Self.authorCredit)"
        }

        let menu = NSMenu()
        appNameItem.isEnabled = false
        authorItem.isEnabled = false
        pauseResumeItem.target = self
        launchAtLoginItem.target = self
        pauseWhenFullscreenItem.target = self
        pauseWhenOnBatteryItem.target = self

        menu.addItem(appNameItem)
        menu.addItem(authorItem)
        menu.addItem(.separator())
        menu.addItem(pauseResumeItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(pauseWhenFullscreenItem)
        menu.addItem(pauseWhenOnBatteryItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 / Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
        updateMenuItems()
    }

    @objc private func togglePause() {
        wallpaperController.togglePause()
        updateMenuItems()
    }

    @objc private func toggleLaunchAtLogin() {
        var settings = wallpaperController.settings
        settings.launchAtLogin.toggle()

        do {
            try LoginItemManager.setEnabled(settings.launchAtLogin)
        } catch {
            NSSound.beep()

            if LoginItemManager.state == .requiresApproval {
                LoginItemManager.openSystemSettings()
            } else {
                settings.launchAtLogin = LoginItemManager.state == .enabled
            }
        }

        wallpaperController.updateSettings(settings)
        updateMenuItems()
    }

    @objc private func togglePauseWhenFullscreen() {
        var settings = wallpaperController.settings
        settings.pauseWhenAllScreensAreFullscreen.toggle()
        wallpaperController.updateSettings(settings)
        updateMenuItems()
    }

    @objc private func togglePauseWhenOnBattery() {
        var settings = wallpaperController.settings
        settings.pauseWhenOnBattery.toggle()
        wallpaperController.updateSettings(settings)
        updateMenuItems()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateMenuItems() {
        let settings = wallpaperController.settings

        pauseResumeItem.title = wallpaperController.isManuallyPaused ? "继续 / Resume" : "暂停 / Pause"
        pauseResumeItem.state = wallpaperController.isManuallyPaused ? .on : .off

        launchAtLoginItem.title = launchAtLoginTitle(for: settings)
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off

        pauseWhenFullscreenItem.state = settings.pauseWhenAllScreensAreFullscreen ? .on : .off
        pauseWhenOnBatteryItem.state = settings.pauseWhenOnBattery ? .on : .off
    }

    private func launchAtLoginTitle(for settings: AppSettings) -> String {
        if settings.launchAtLogin, LoginItemManager.state == .requiresApproval {
            return "开机自启动（需允许）/ Launch at Login (Approval Needed)"
        }

        return "开机自启动 / Launch at Login"
    }
}
