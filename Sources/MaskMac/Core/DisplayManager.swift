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
    private var refreshDeadline: TimeInterval?
    private var restoreMonitorWorkItem: DispatchWorkItem?
    private let configurationQueue = DispatchQueue(label: "local.maskmac.display-configuration", qos: .userInitiated)
    private var isApplying = false
    private var transition: DisplayTransition?
    private var recoveryNotBefore: TimeInterval = 0
    private var terminationReply: ((Bool) -> Void)?
    private(set) var isPreparingToQuit = false
    var isTransitioning: Bool { isApplying || transition != nil }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
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
        guard !isTransitioning, !isPreparingToQuit else { return }
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
            if isPreparingToQuit { finishTermination(success: false) }
            if showError {
                presentError("没有找到之前保存的内建显示器 ID。")
            }
            return
        }
        guard isInternalDisplayOff else { return }
        apply(enabled: true, displayID: displayID, showError: showError)
    }

    func prepareForTermination(completion: @escaping (Bool) -> Void) {
        guard !isPreparingToQuit else { return }
        isPreparingToQuit = true
        terminationReply = completion
        NotificationCenter.default.post(name: .displayManagerDidUpdate, object: self)
        continueTermination()
    }

    private func continueTermination() {
        guard isPreparingToQuit, !isApplying else { return }
        if restoreOnQuit && isInternalDisplayOff {
            enableInternalDisplay(showError: false)
        } else if transition == nil || !restoreOnQuit {
            finishTermination(success: true)
        }
    }

    private func finishTermination(success: Bool) {
        let reply = terminationReply
        terminationReply = nil
        isPreparingToQuit = false
        NotificationCenter.default.post(name: .displayManagerDidUpdate, object: self)
        reply?(success)
        if !success { presentError("内建屏幕尚未恢复，已取消退出。请再次尝试关闭 Extend。") }
    }

    private func apply(enabled: Bool, displayID: CGDirectDisplayID, showError: Bool = true) {
        guard !isApplying else { return }
        guard let configure = PrivateDisplayAPI.configureDisplayEnabled else {
            if showError { presentError("当前系统找不到显示配置接口。") }
            if isPreparingToQuit { finishTermination(success: false) }
            return
        }

        transition = nil
        isApplying = true
        let startedAt = now
        NotificationCenter.default.post(name: .displayManagerDidUpdate, object: self)

        // WindowServer 的同步提交可能等待硬件握手；只把事务放到串行队列，AppKit 与状态仍留在主线程。
        configurationQueue.async { [weak self] in
            var configuration: CGDisplayConfigRef?
            var result = CGBeginDisplayConfiguration(&configuration)
            if result == .success {
                result = configure(configuration, displayID, enabled)
                if result == .success {
                    // 不添加 FadeEffect：本机设置时成功，但会使整笔提交返回 notImplemented (1006)。
                    result = CGCompleteDisplayConfiguration(configuration, .forSession)
                } else {
                    CGCancelDisplayConfiguration(configuration)
                }
            }
            let resultCode = result.rawValue
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            NSLog("MaskMac display=%u enabled=%@ commit=%.3fs result=%d",
                  displayID, enabled ? "true" : "false", elapsed, resultCode)
            DispatchQueue.main.async { [weak self] in
                self?.configurationCompleted(enabled: enabled, resultCode: resultCode, showError: showError)
            }
        }
    }

    private func configurationCompleted(enabled: Bool, resultCode: Int32, showError: Bool) {
        isApplying = false
        guard resultCode == CGError.success.rawValue else {
            if isPreparingToQuit { finishTermination(success: false) }
            if showError { presentError("显示配置失败（错误码 \(resultCode)）。") }
            scheduleRefresh(after: 0.1)
            return
        }

        isInternalDisplayOff = !enabled
        UserDefaults.standard.set(isInternalDisplayOff, forKey: DefaultsKey.internalDisplayOff)
        transition = DisplayTransition(enabled: enabled, startedAt: now)
        // 链路重训保护独立于按钮忙碌状态，拓扑稳定即可交互，无须固定等满四秒。
        recoveryNotBefore = enabled ? 0 : now + 4.0
        if enabled { stopRestoreMonitor() } else { startRestoreMonitor() }
        if isPreparingToQuit && !enabled {
            continueTermination()
        }
        refresh()
    }

    private func refresh() {
        var activeDisplayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &activeDisplayCount) == .success else {
            scheduleRefresh(after: 0.1)
            return
        }
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: max(1, Int(activeDisplayCount)))
        let listResult = activeDisplays.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(UInt32(buffer.count), buffer.baseAddress, &activeDisplayCount)
        }
        guard listResult == .success else {
            scheduleRefresh(after: 0.1)
            return
        }
        activeDisplays = Array(activeDisplays.prefix(Int(activeDisplayCount)))

        let physicalExternalIDs = activeDisplays.filter { CGDisplayIsBuiltin($0) == 0 && isPhysicalExternalDisplay($0) }
        if !physicalExternalIDs.isEmpty {
            let ids = Set(physicalExternalIDs)
            if ids != knownExternalDisplayIDs {
                knownExternalDisplayIDs = ids
                persistKnownExternalIDs()
            }
        }

        let externalCount = physicalExternalIDs.count
        var foundInternalID: CGDirectDisplayID?
        for displayID in activeDisplays {
            if CGDisplayIsBuiltin(displayID) != 0 {
                foundInternalID = displayID
                internalDisplayUUID = uuidString(for: displayID)
            }
        }

        logDisplayTopology(activeDisplays)
        if var pending = transition {
            let outcome = pending.observe(internalActive: foundInternalID != nil,
                                          externalIDs: Set(physicalExternalIDs), now: now)
            transition = outcome == .waiting ? pending : nil
            if outcome != .waiting {
                NSLog("MaskMac display settled=%@ afterCommit=%.3fs",
                      outcome == .settled ? "true" : "false", now - pending.startedAt)
                if outcome == .timedOut && pending.enabled && foundInternalID == nil {
                    // 接口成功不等于内屏已恢复；保留恢复入口与拔线兜底，退出也不得提前放行。
                    isInternalDisplayOff = true
                    UserDefaults.standard.set(true, forKey: DefaultsKey.internalDisplayOff)
                }
                if isPreparingToQuit && pending.enabled {
                    finishTermination(success: foundInternalID != nil)
                }
            }
        }
        if let foundInternalID, !isTransitioning, now >= recoveryNotBefore {
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

        if isInternalDisplayOff && externalCount == 0 && !isTransitioning && now >= recoveryNotBefore {
            enableInternalDisplay(showError: false)
            if isInternalDisplayOff {
                startRestoreMonitor()
            }
        } else if isInternalDisplayOff {
            startRestoreMonitor()
        }
        if transition != nil { scheduleRefresh(after: 0.1) }
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

    private func scheduleRefresh(after delay: TimeInterval = 0.1) {
        // 合并事件而不反复向后推迟，避免连续回调使刷新一直无法执行。
        let deadline = now + delay
        if let refreshDeadline, refreshDeadline <= deadline { return }
        refreshWorkItem?.cancel()
        refreshDeadline = deadline
        let item = DispatchWorkItem { [weak self] in
            self?.refreshWorkItem = nil
            self?.refreshDeadline = nil
            self?.refresh()
        }
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
        if knownExternalDisplayIDs.contains(displayID) {
            return true
        }
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
            scheduleRefresh(after: 0.1)
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
