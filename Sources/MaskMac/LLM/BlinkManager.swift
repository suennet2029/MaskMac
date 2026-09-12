import Foundation
import AppKit

@MainActor
final class BlinkManager {
    static let shared = BlinkManager()

    private enum DefaultsKey {
        static let isEnabled = "BlinkEnabled"
    }

    private var pollTimer: Timer?
    private var simulationTimer: Timer?
    private var isSimulating: Bool = false
    private var autoActive: Bool = false

    private(set) var currentAgent: String?

    var isBlinking: Bool {
        KeyboardLEDManager.shared.isBlinking
    }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
            NotificationCenter.default.post(name: .blinkStateDidUpdate, object: self)
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
        // 启动时立即扫描一次
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
        KeyboardLEDManager.shared.stopBlinking()
    }

    /// 模拟测试 5 秒闪烁
    func startSimulation(duration: TimeInterval = 5.0) {
        simulationTimer?.invalidate()
        isSimulating = true
        currentAgent = "Test"
        KeyboardLEDManager.shared.startBlinking(interval: 0.35)
        NotificationCenter.default.post(name: .blinkStateDidUpdate, object: self)

        simulationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSimulating else { return }
                self.isSimulating = false
                self.currentAgent = nil
                KeyboardLEDManager.shared.stopBlinking()
                NotificationCenter.default.post(name: .blinkStateDidUpdate, object: self)
            }
        }
    }

    /// 检测本地 Claude Code、CodeX 和 antiGravity 运行状态
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
                // 3. antiGravity (包括 Antigravity.app、language_server 以及 agy CLI)
                if lower.contains("antigravity") || lower.contains("/agy") || lower.hasPrefix("agy ") {
                    detected = true
                    agentName = "antiGravity"
                    break
                }
            }

            if detected && !autoActive {
                autoActive = true
                currentAgent = agentName
                KeyboardLEDManager.shared.startBlinking(interval: 0.35)
                NotificationCenter.default.post(name: .blinkStateDidUpdate, object: self)
            } else if !detected && autoActive {
                autoActive = false
                currentAgent = nil
                KeyboardLEDManager.shared.stopBlinking()
                NotificationCenter.default.post(name: .blinkStateDidUpdate, object: self)
            }
        } catch {
        }
    }
}
