import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let displayManager = DisplayManager()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("正在监测外接显示器断开")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        rebuildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenuNotification),
            name: .displayManagerDidUpdate,
            object: displayManager
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if displayManager.restoreOnQuit {
            displayManager.enableInternalDisplay(showError: false)
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func rebuildMenuNotification() {
        rebuildMenu()
    }

    @objc private func toggleDisplay() {
        displayManager.toggleInternalDisplay()
        rebuildMenu()
    }

    @objc private func showSettings() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "显示器设置"
        alert.informativeText = "应用采用手动模式：连接外接显示器后，请从菜单手动关闭内建显示器；拔线时应用会自动恢复内屏。"

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 62))
        let statusLabel = NSTextField(
            labelWithString: "当前状态：\(displayManager.isInternalDisplayOff ? "内建显示器已关闭" : "内建显示器已开启") · 外接显示器：\(displayManager.externalDisplayCount) 台"
        )
        statusLabel.frame = NSRect(x: 0, y: 36, width: 360, height: 22)
        accessoryView.addSubview(statusLabel)

        let restoreOnQuit = NSButton(
            checkboxWithTitle: "退出应用时恢复内建显示器（推荐）",
            target: nil,
            action: nil
        )
        restoreOnQuit.frame = NSRect(x: 0, y: 6, width: 360, height: 24)
        restoreOnQuit.state = displayManager.restoreOnQuit ? .on : .off
        accessoryView.addSubview(restoreOnQuit)

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        displayManager.restoreOnQuit = restoreOnQuit.state == .on
        rebuildMenu()
    }

    @objc private func quitApp() {
        if displayManager.restoreOnQuit {
            displayManager.enableInternalDisplay(showError: false)
        }
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
        menu.removeAllItems()

        let toggleTitle = displayManager.isInternalDisplayOff ? "恢复内建显示器" : "只保留外接显示器"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleDisplay), keyEquivalent: "d")
        toggle.target = self
        toggle.isEnabled = displayManager.isInternalDisplayOff
            ? displayManager.internalDisplayID != nil
            : displayManager.externalDisplayCount > 0
        menu.addItem(toggle)

        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MaskMac", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }
}
