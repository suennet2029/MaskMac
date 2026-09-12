import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let displayManager = DisplayManager()
    private let duoPreferences = DuoPreferences.shared
    private lazy var lidController = LidController(preferences: duoPreferences)
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let extendItem = NSMenuItem(title: "Extend", action: #selector(toggleDisplay), keyEquivalent: "d")
    private let duoItem = NSMenuItem(title: "Duo", action: #selector(toggleDuoEffect), keyEquivalent: "")
    private let exitItem = NSMenuItem(title: "Exit", action: #selector(quitApp), keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("正在监测外接显示器与开合传感器")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        lidController.start()
        rebuildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenuNotification),
            name: .displayManagerDidUpdate,
            object: displayManager
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 退出也走同一个串行事务，避免后台正在关屏时进程先退出。
        DispatchQueue.main.async { [weak self] in
            self?.displayManager.prepareForTermination { success in
                sender.reply(toApplicationShouldTerminate: success)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        lidController.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func rebuildMenuNotification() {
        rebuildMenu()
    }

    @objc private func toggleDisplay() {
        menu.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            self?.displayManager.toggleInternalDisplay()
        }
    }

    @objc private func toggleDuoEffect() {
        duoPreferences.isEnabled.toggle()
        if duoPreferences.isEnabled {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
        }
        rebuildMenu()
    }

    @objc private func quitApp() {
        menu.cancelTracking()
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        if let iconURL = Bundle.main.url(forResource: "maskmac-menu-icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 20, height: 20)
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "MaskMac"
        } else {
            button.title = "▣"
        }
    }

    private func rebuildMenu() {
        if menu.items.isEmpty {
            menu.autoenablesItems = false
            for item in [extendItem, duoItem, exitItem] { item.target = self }
            menu.addItem(extendItem)
            menu.addItem(.separator())
            menu.addItem(duoItem)
            menu.addItem(.separator())
            menu.addItem(exitItem)
            statusItem.menu = menu
        }

        let busy = displayManager.isTransitioning
        extendItem.title = busy ? "Extend…" : "Extend"
        extendItem.state = busy ? .mixed : (displayManager.isInternalDisplayOff ? .on : .off)
        extendItem.isEnabled = !busy && !displayManager.isPreparingToQuit && (displayManager.isInternalDisplayOff
            ? displayManager.internalDisplayID != nil
            : displayManager.externalDisplayCount > 0)
        statusItem.button?.toolTip = busy ? "MaskMac — 正在切换显示器" : "MaskMac"
        duoItem.state = duoPreferences.isEnabled ? .on : .off
        duoItem.isEnabled = lidController.isSensorAvailable
        duoItem.title = lidController.isSensorAvailable ? "Duo" : "Duo (No Sensor)"
        exitItem.isEnabled = !displayManager.isPreparingToQuit
    }
}
