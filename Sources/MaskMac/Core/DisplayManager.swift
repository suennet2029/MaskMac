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
    private var lastDisplaySignature = ""
    private var knownExternalDisplayIDs: Set<CGDirectDisplayID>

    init() {
        let defaults = UserDefaults.standard
        // 清理旧版本自动切换配置，避免遗留偏好继续影响用户判断。
        defaults.removeObject(forKey: "AutoDisableWithExternal")
        defaults.removeObject(forKey: "AutoDisableDelay")
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
        } else {
            startRestoreMonitor()
        }
    }

    private func refresh() {
        var activeDisplayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &activeDisplayCount)
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(activeDisplayCount))
        _ = activeDisplays.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(activeDisplayCount, buffer.baseAddress, &activeDisplayCount)
        }

        let activeExternalDisplayIDs = activeDisplays.filter { CGDisplayIsBuiltin($0) == 0 }
        if !isInternalDisplayOff || knownExternalDisplayIDs.isEmpty {
            let physicalExternalIDs = activeExternalDisplayIDs.filter(isPhysicalExternalDisplay)
            if !physicalExternalIDs.isEmpty {
                knownExternalDisplayIDs = Set(physicalExternalIDs)
                persistKnownExternalIDs()
            }
        }

        var externalCount = 0
        var foundInternalID: CGDirectDisplayID?
        for displayID in activeDisplays {
            if CGDisplayIsBuiltin(displayID) != 0 {
                foundInternalID = displayID
                internalDisplayUUID = uuidString(for: displayID)
            } else if knownExternalDisplayIDs.contains(displayID), isPhysicalExternalDisplay(displayID) {
                externalCount += 1
            }
        }

        logDisplayTopology(activeDisplays)
        if let foundInternalID {
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

        if isInternalDisplayOff && externalCount == 0 {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func stopRestoreMonitor() {
        restoreMonitorWorkItem?.cancel()
        restoreMonitorWorkItem = nil
    }

    private func isPhysicalExternalDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        let size = CGDisplayScreenSize(displayID)
        let hasPhysicalSize = size.width >= 10 && size.height >= 10
        let hasHardwareIdentity = CGDisplayVendorNumber(displayID) != 0 || CGDisplayModelNumber(displayID) != 0
        return hasPhysicalSize && hasHardwareIdentity
    }

    func handleDisplayReconfiguration(flags: CGDisplayChangeSummaryFlags) {
        let removalFlags: CGDisplayChangeSummaryFlags = [.removeFlag, .disabledFlag]
        if !flags.intersection(removalFlags).isEmpty || isInternalDisplayOff {
            refresh()
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
