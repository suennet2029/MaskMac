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
        scanProcesses()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scanProcesses()
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
        TopRunnerWindow.shared.hide()
        KeyboardBrightnessManager.shared.stopBreathing()
    }

    /// 模拟测试 5 秒（顶部激光跑马灯 + 键盘背光呼吸）
    func startSimulation(duration: TimeInterval = 5.0) {
        simulationTimer?.invalidate()
        isSimulating = true
        currentAgent = "Test"
        TopRunnerWindow.shared.show()
        KeyboardBrightnessManager.shared.startBreathing()
        NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)

        simulationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSimulating else { return }
                self.isSimulating = false
                self.currentAgent = nil
                TopRunnerWindow.shared.hide()
                KeyboardBrightnessManager.shared.stopBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            }
        }
    }

    /// 扫描检测本地运行的 Claude Code、CodeX 与 antiGravity 进程
    private func scanProcesses() {
        guard !isSimulating, isEnabled else { return }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-A", "-o", "comm=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return }
            var detected = false
            var agentName = ""

            for line in output.split(separator: "\n") {
                let lower = line.lowercased()
                if lower.contains("grep") || lower.contains("maskmac") { continue }

                // 1. Claude Code
                if lower.contains("claude") {
                    detected = true
                    agentName = "Claude Code"
                    break
                }
                // 2. CodeX
                if lower.contains("codex") {
                    detected = true
                    agentName = "CodeX"
                    break
                }
                // 3. antiGravity (包含 Antigravity.app、language_server 以及 agy CLI)
                if lower.contains("antigravity") || lower.contains("/agy") || lower.hasPrefix("agy ") {
                    detected = true
                    agentName = "antiGravity"
                    break
                }
            }

            if detected && !autoActive {
                autoActive = true
                currentAgent = agentName
                TopRunnerWindow.shared.show()
                KeyboardBrightnessManager.shared.startBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            } else if !detected && autoActive {
                autoActive = false
                currentAgent = nil
                TopRunnerWindow.shared.hide()
                KeyboardBrightnessManager.shared.stopBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            }
        } catch {
        }
    }
}
