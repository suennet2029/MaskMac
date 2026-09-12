import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let displayManager = DisplayManager()
    private let duoPreferences = DuoPreferences.shared
    private lazy var lidController = LidController(preferences: duoPreferences)
    private let auraManager = AuraManager.shared

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let extendItem = NSMenuItem(title: "Extend", action: #selector(toggleDisplay), keyEquivalent: "d")
    private let duoItem = NSMenuItem(title: "Duo", action: #selector(toggleDuoEffect), keyEquivalent: "")
    private let brightnessItem = NSMenuItem(title: "Brightness", action: #selector(toggleBrightness), keyEquivalent: "b")
    private let auraItem = NSMenuItem(title: "Aura", action: #selector(toggleAura), keyEquivalent: "")
    private let exitItem = NSMenuItem(title: "Exit", action: #selector(quitApp), keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("正在监测外接显示器、传感器与任务状态")

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenuNotification),
            name: .auraStateDidUpdate,
            object: nil
        )

        handleCommandLineArguments()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        auraManager.stopMonitoring()
        BrightnessPanelWindow.shared.hide()
        DispatchQueue.main.async { [weak self] in
            self?.displayManager.prepareForTermination { success in
                sender.reply(toApplicationShouldTerminate: success)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        auraManager.stopMonitoring()
        BrightnessPanelWindow.shared.hide()
        lidController.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func handleCommandLineArguments() {
        let args = CommandLine.arguments
        if args.contains("--aura-test") {
            auraManager.startSimulation(duration: 5.0)
        } else if args.contains("--brightness") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleBrightness()
            }
        }
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

    @objc private func toggleBrightness() {
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            BrightnessPanelWindow.shared.toggle(relativeTo: button)
        }
    }

    @objc private func toggleAura() {
        auraManager.toggle()
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
            for item in [extendItem, duoItem, brightnessItem, auraItem, exitItem] {
                item.target = self
            }
            menu.addItem(extendItem)
            menu.addItem(.separator())
            menu.addItem(duoItem)
            menu.addItem(.separator())
            menu.addItem(brightnessItem)
            menu.addItem(auraItem)
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

        duoItem.state = duoPreferences.isEnabled ? .on : .off
        duoItem.isEnabled = lidController.isSensorAvailable
        duoItem.title = lidController.isSensorAvailable ? "Duo" : "Duo (No Sensor)"

        auraItem.state = auraManager.isEnabled ? .on : .off
        if let agent = auraManager.currentAgent {
            auraItem.title = "Aura (\(agent))"
        } else {
            auraItem.title = "Aura"
        }

        if busy {
            statusItem.button?.toolTip = "MaskMac — 正在切换显示器"
        } else if auraManager.isActive {
            statusItem.button?.toolTip = "MaskMac — \(auraManager.currentAgent ?? "Agent") 运行中 (顶部跑马灯 & 键盘呼吸)"
        } else {
            statusItem.button?.toolTip = "MaskMac"
        }

        exitItem.isEnabled = !displayManager.isPreparingToQuit
    }
}
