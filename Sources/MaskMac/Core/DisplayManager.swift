import AppKit
import CoreGraphics
import Foundation

private func displayReconfigurationCallback(
    _ : CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { [weak manager] in
        manager?.handleDisplayReconfiguration(flags: flags)
    }
}

@MainActor
final class DisplayManager {
    private enum DefaultsKey {
        static let internalDisplayID = "InternalDisplayID"
        static let internalDisplayUUID = "InternalDisplayUUID"
        static let internalDisplayOff = "InternalDisplayOff"
        static let restoreOnQuit = "RestoreOnQuit"
        static let knownExternalDisplayIDs = "KnownExternalDisplayIDs"
    }

    private(set) var internalDisplayID: CGDirectDisplayID?
    private(set) var internalDisplayUUID: String?
    private(set) var isInternalDisplayOff: Bool
    private(set) var externalDisplayCount = 0

    var restoreOnQuit: Bool {
        didSet {
            UserDefaults.standard.set(restoreOnQuit, forKey: DefaultsKey.restoreOnQuit)
        }
    }

    private var refreshWorkItem: DispatchWorkItem?
    private var restoreMonitorWorkItem: DispatchWorkItem?
    /// 状态切换过渡锁：在执行开启/关闭内建屏后锁定 1.5 秒，避免通道断开/握手期间的回调震荡
    private var isTransitioning = false
    private var lastDisplaySignature = ""
    private var knownExternalDisplayIDs: Set<CGDirectDisplayID>

    init() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "AutoDisableWithExternal")
        defaults.removeObject(forKey: "AutoDisableDelay")
        defaults.removeObject(forKey: "MaskMode")
        defaults.removeObject(forKey: "ActiveOffMode")
        defaults.removeObject(forKey: "SavedBrightness")
        defaults.removeObject(forKey: "SavedInternalOriginX")
        defaults.removeObject(forKey: "SavedInternalOriginY")

        if let storedID = defaults.object(forKey: DefaultsKey.internalDisplayID) as? Int {
            internalDisplayID = CGDirectDisplayID(storedID)
        } else if let storedID = defaults.object(forKey: DefaultsKey.internalDisplayID) as? UInt32 {
            internalDisplayID = storedID
        }
        internalDisplayUUID = defaults.string(forKey: DefaultsKey.internalDisplayUUID)
        isInternalDisplayOff = defaults.bool(forKey: DefaultsKey.internalDisplayOff)
        restoreOnQuit = defaults.object(forKey: DefaultsKey.restoreOnQuit) as? Bool ?? true
        let storedExternalIDs = defaults.array(forKey: DefaultsKey.knownExternalDisplayIDs) as? [Int] ?? []
        knownExternalDisplayIDs = Set(storedExternalIDs.map(CGDirectDisplayID.init))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        refresh()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func toggleInternalDisplay() {
        if isInternalDisplayOff {
            enableInternalDisplay()
        } else {
            disableInternalDisplay()
        }
    }

    func disableInternalDisplay() {
        refresh()
        guard externalDisplayCount > 0 else {
            presentError("没有检测到真实的外接显示器，已阻止关闭内屏。")
            return
        }
        guard let displayID = internalDisplayID else {
            presentError("无法识别内建显示器。")
            return
        }
        guard !isInternalDisplayOff else { return }

        apply(enabled: false, displayID: displayID)
    }

    func enableInternalDisplay(showError: Bool = true) {
        guard let displayID = internalDisplayID else {
            if showError {
                presentError("没有找到之前保存的内建显示器 ID。")
            }
            return
        }
        guard isInternalDisplayOff else { return }
        apply(enabled: true, displayID: displayID, showError: showError)
    }

    private func apply(enabled: Bool, displayID: CGDirectDisplayID, showError: Bool = true) {
        guard let configure = PrivateDisplayAPI.configureDisplayEnabled else {
            if showError {
                presentError("当前系统找不到显示配置接口。")
            }
            return
        }

        isTransitioning = true

        var configuration: CGDisplayConfigRef?
        var result = CGBeginDisplayConfiguration(&configuration)
        if result == .success {
            result = configure(configuration, displayID, enabled)
        }
        if result == .success {
            result = CGCompleteDisplayConfiguration(
                configuration,
                enabled ? .permanently : .forSession
            )
        }
        if result != .success {
            CGCancelDisplayConfiguration(configuration)
        }

        NSLog(
            "MaskMac display=%u enabled=%@ result=%d",
            displayID,
            enabled ? "true" : "false",
            result.rawValue
        )

        guard result == .success else {
            isTransitioning = false
            if showError {
                presentError("显示配置失败（错误码 \(result.rawValue)）。")
            }
            return
        }

        isInternalDisplayOff = !enabled
        UserDefaults.standard.set(isInternalDisplayOff, forKey: DefaultsKey.internalDisplayOff)
        if enabled {
            stopRestoreMonitor()
            scheduleRefresh(after: 1.0)
            refreshMenuBarLayout()
        } else {
            startRestoreMonitor()
        }

        // 切换后保留 1.5 秒过渡期，在此期间不因系统重协商回调把内屏误判为开启或把外接屏误判为断开
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.isTransitioning = false
            self.refresh()
        }
    }

    private func refresh() {
        var activeDisplayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &activeDisplayCount)
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(activeDisplayCount))
        _ = activeDisplays.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(activeDisplayCount, buffer.baseAddress, &activeDisplayCount)
        }

        let physicalExternalIDs = activeDisplays.filter { CGDisplayIsBuiltin($0) == 0 && isPhysicalExternalDisplay($0) }
        if !physicalExternalIDs.isEmpty {
            knownExternalDisplayIDs = Set(physicalExternalIDs)
            persistKnownExternalIDs()
        }

        var externalCount = 0
        var foundInternalID: CGDirectDisplayID?
        for displayID in activeDisplays {
            if CGDisplayIsBuiltin(displayID) != 0 {
                foundInternalID = displayID
                internalDisplayUUID = uuidString(for: displayID)
            } else if isPhysicalExternalDisplay(displayID) {
                externalCount += 1
            }
        }

        logDisplayTopology(activeDisplays)
        if let foundInternalID, !isTransitioning {
            internalDisplayID = foundInternalID
            UserDefaults.standard.set(Int(foundInternalID), forKey: DefaultsKey.internalDisplayID)
            if let internalDisplayUUID {
                UserDefaults.standard.set(internalDisplayUUID, forKey: DefaultsKey.internalDisplayUUID)
            }
            if isInternalDisplayOff {
                isInternalDisplayOff = false
                UserDefaults.standard.set(false, forKey: DefaultsKey.internalDisplayOff)
                stopRestoreMonitor()
            }
        }
        self.externalDisplayCount = externalCount

        if isInternalDisplayOff && externalCount == 0 && !isTransitioning {
            enableInternalDisplay(showError: false)
            if isInternalDisplayOff {
                startRestoreMonitor()
            }
        } else if isInternalDisplayOff {
            startRestoreMonitor()
        }
        NotificationCenter.default.post(name: .displayManagerDidUpdate, object: self)
    }

    private func persistKnownExternalIDs() {
        UserDefaults.standard.set(
            knownExternalDisplayIDs.map(Int.init).sorted(),
            forKey: DefaultsKey.knownExternalDisplayIDs
        )
    }

    private func logDisplayTopology(_ displays: [CGDirectDisplayID]) {
        let signature = displays.map { displayID in
            let size = CGDisplayScreenSize(displayID)
            let known = knownExternalDisplayIDs.contains(displayID)
            return "id=\(displayID),builtin=\(CGDisplayIsBuiltin(displayID)),known=\(known),vendor=\(CGDisplayVendorNumber(displayID)),model=\(CGDisplayModelNumber(displayID)),mm=\(Int(size.width))x\(Int(size.height))"
        }.joined(separator: ";")
        guard signature != lastDisplaySignature else { return }
        NSLog("MaskMac active displays: %@", signature)
        lastDisplaySignature = signature
    }

    private func scheduleRefresh(after delay: TimeInterval = 0.35) {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func startRestoreMonitor() {
        guard restoreMonitorWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restoreMonitorWorkItem = nil
            guard self.isInternalDisplayOff else { return }
            self.refresh()
            if self.isInternalDisplayOff {
                self.startRestoreMonitor()
            }
        }
        restoreMonitorWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func stopRestoreMonitor() {
        restoreMonitorWorkItem?.cancel()
        restoreMonitorWorkItem = nil
    }

    /// 判定是否为真实存在的物理外接显示器
    /// 排除虚拟屏幕、AirPlay 占位符以及系统在分辨率/HDR重协商瞬间生成的临时无物理尺寸占位符
    private func isPhysicalExternalDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        let size = CGDisplayScreenSize(displayID)
        let hasPhysicalSize = size.width >= 10 && size.height >= 10
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        // 过滤系统在显示重协商阶段生成的临时占位（如 vendor="unkn", model="virt"）
        let isVirtual = (vendor == 0x756e6b6e && model == 0x76697274)
        let hasHardwareIdentity = (vendor != 0 || model != 0) && !isVirtual
        return hasPhysicalSize && hasHardwareIdentity
    }

    func handleDisplayReconfiguration(flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            return
        }
        let removalFlags: CGDisplayChangeSummaryFlags = [.removeFlag, .disabledFlag]
        if !flags.intersection(removalFlags).isEmpty || isInternalDisplayOff {
            scheduleRefresh(after: 0.2)
        }
    }

    /// 刷新顶部菜单栏布局
    /// 在 macOS Sequoia 下重新点亮内屏或变更主显示器后，ControlCenter 托盘图标易出现重叠错位，
    /// 通过触发 ControlCenter 进程重启，重置菜单栏布局。
    private func refreshMenuBarLayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["ControlCenter"]
            try? task.run()
        }
    }

    private func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeUnretainedValue()) as String
    }

    private func presentError(_ message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "MaskMac"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
        NotificationCenter.default.post(name: .displayManagerDidUpdate, object: self)
    }

    @objc private func screenParametersChanged() {
        scheduleRefresh()
        if isInternalDisplayOff {
            startRestoreMonitor()
        }
    }

    @objc private func wakeFromSleep() {
        scheduleRefresh(after: isInternalDisplayOff ? 2.0 : 1.0)
        if isInternalDisplayOff {
            startRestoreMonitor()
        }
    }
}
