import Foundation
import AppKit

@MainActor
final class AuraManager {
    static let shared = AuraManager()

    private enum DefaultsKey {
        static let isEnabled = "AuraEnabled"
    }

    private var pollTimer: Timer?
    private var simulationTimer: Timer?
    private var isSimulating: Bool = false
    private var autoActive: Bool = false

    private(set) var currentAgent: String?

    var isActive: Bool {
        autoActive || isSimulating
    }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
            NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: DefaultsKey.isEnabled) as? Bool ?? true
        if isEnabled {
            startMonitoring()
        }
    }

    func toggle() {
        isEnabled.toggle()
    }

    func startMonitoring() {
        pollTimer?.invalidate()
        scanActivity()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scanActivity()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        simulationTimer?.invalidate()
        simulationTimer = nil
        isSimulating = false
        autoActive = false
        currentAgent = nil
        ScreenAuraWindow.shared.hide()
        KeyboardBrightnessManager.shared.stopBreathing()
    }

    /// 模拟测试 5 秒（顶部激光跑马灯 + 键盘背光呼吸）
    func startSimulation(duration: TimeInterval = 5.0) {
        simulationTimer?.invalidate()
        isSimulating = true
        currentAgent = "Test"
        ScreenAuraWindow.shared.show()
        KeyboardBrightnessManager.shared.startBreathing()
        NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)

        simulationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSimulating else { return }
                self.isSimulating = false
                self.currentAgent = nil
                ScreenAuraWindow.shared.hide()
                KeyboardBrightnessManager.shared.stopBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            }
        }
    }

    /// 动态检测当前是否真正处于“正在运行/推理中”的状态
    private func scanActivity() {
        guard !isSimulating, isEnabled else { return }

        if let activeAgent = detectCurrentlyActiveAgent() {
            if !autoActive || currentAgent != activeAgent {
                autoActive = true
                currentAgent = activeAgent
                ScreenAuraWindow.shared.show()
                KeyboardBrightnessManager.shared.startBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            }
        } else {
            if autoActive {
                autoActive = false
                currentAgent = nil
                ScreenAuraWindow.shared.hide()
                KeyboardBrightnessManager.shared.stopBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            }
        }
    }

    private func detectCurrentlyActiveAgent() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // 1. antiGravity：仅在真正执行任务/生成时会有日志与轨迹实时更新（3 秒内有写入）
        let brainURL = home.appendingPathComponent(".gemini/antigravity/brain")
        if isDirectoryRecentlyActive(brainURL, maxDepth: 4, seconds: 3.0) {
            return "antiGravity"
        }

        // 2. Claude Code：仅在真正执行生成任务时会写会话/历史（3 秒内有写入）
        let claudeURL = home.appendingPathComponent(".claude")
        if isDirectoryRecentlyActive(claudeURL.appendingPathComponent("sessions"), maxDepth: 2, seconds: 3.0) ||
           isDirectoryRecentlyActive(claudeURL.appendingPathComponent("projects"), maxDepth: 3, seconds: 3.0) ||
           isPathRecent(claudeURL.appendingPathComponent("history.jsonl"), seconds: 3.0) {
            return "Claude Code"
        }

        // 3. CodeX：仅在真正执行任务时会写 wal 数据库与状态（3 秒内有写入）
        let codexURL = home.appendingPathComponent(".codex")
        if isPathRecent(codexURL.appendingPathComponent("logs_2.sqlite-wal"), seconds: 3.0) ||
           isPathRecent(codexURL.appendingPathComponent("goals_1.sqlite-wal"), seconds: 3.0) ||
           isPathRecent(codexURL.appendingPathComponent(".codex-global-state.json"), seconds: 3.0) ||
           isDirectoryRecentlyActive(codexURL.appendingPathComponent("sessions"), maxDepth: 2, seconds: 3.0) {
            return "CodeX"
        }

        return nil
    }

    private func isDirectoryRecentlyActive(_ url: URL, maxDepth: Int = 3, seconds: TimeInterval = 3.0) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let now = Date()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else { return false }

        for case let fileURL as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
               attrs.isRegularFile == true,
               let mtime = attrs.contentModificationDate {
                if now.timeIntervalSince(mtime) < seconds {
                    return true
                }
            }
        }
        return false
    }

    private func isPathRecent(_ url: URL, seconds: TimeInterval = 3.0) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mtime) < seconds
    }
}
