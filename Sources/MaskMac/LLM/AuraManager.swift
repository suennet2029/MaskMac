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
    private var pendingHideWorkItem: DispatchWorkItem?
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
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        isSimulating = false
        autoActive = false
        currentAgent = nil
        ScreenAuraWindow.shared.hide()
        KeyboardBrightnessManager.shared.stopBreathing()
    }

    /// 模拟测试 5 秒（全屏 Apple Intelligence 光晕 + 键盘背光呼吸）
    func startSimulation(duration: TimeInterval = 5.0) {
        simulationTimer?.invalidate()
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
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
            // 取消延迟熄灭计时器
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil

            if !autoActive || currentAgent != activeAgent {
                autoActive = true
                currentAgent = activeAgent
                ScreenAuraWindow.shared.show()
                KeyboardBrightnessManager.shared.startBreathing()
                NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
            }
        } else {
            if autoActive {
                // 增加 2.0 秒平滑防抖缓冲（Hysteresis），避免命令执行间隙或思考停顿造成光晕忽明忽暗
                if pendingHideWorkItem == nil {
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self, self.autoActive else { return }
                        if self.detectCurrentlyActiveAgent() == nil {
                            self.autoActive = false
                            self.currentAgent = nil
                            ScreenAuraWindow.shared.hide()
                            KeyboardBrightnessManager.shared.stopBreathing()
                            NotificationCenter.default.post(name: .auraStateDidUpdate, object: self)
                        }
                        self.pendingHideWorkItem = nil
                    }
                    self.pendingHideWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
                }
            }
        }
    }

    private func detectCurrentlyActiveAgent() -> String? {
        // 1. antiGravity
        if isAntiGravityActive() {
            return "antiGravity"
        }

        // 2. CodeX
        if isCodeXActive() {
            return "CodeX"
        }

        // 3. Claude Code
        if isClaudeCodeActive() {
            return "Claude Code"
        }

        return nil
    }

    // MARK: - antiGravity 状态感知
    private func isAntiGravityActive() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let brainDir = home.appendingPathComponent(".gemini/antigravity/brain")
        guard let convoFolders = try? FileManager.default.contentsOfDirectory(at: brainDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return false
        }

        var latestTranscript: URL?
        var latestDate: Date = .distantPast

        for folder in convoFolders {
            let transcriptURL = folder.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            if let attrs = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let mdate = attrs.contentModificationDate,
               mdate > latestDate {
                latestDate = mdate
                latestTranscript = transcriptURL
            }
        }

        guard let transcript = latestTranscript else { return false }
        let age = Date().timeIntervalSince(latestDate)
        if age > 45.0 { return false }

        guard let tail = readTail(of: transcript.path, maxBytes: 65536) else { return false }
        let lines = tail.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let lastLine = lines.last,
              let data = lastLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        let type = json["type"] as? String ?? ""
        if type == "USER_INPUT" || type == "GENERIC" {
            return true
        }
        if type == "PLANNER_RESPONSE" {
            if let tools = json["tool_calls"] as? [[String: Any]], !tools.isEmpty {
                return true
            }
            return false // 最终回复，无后续 tool calls ➔ 本轮任务完成
        }
        return age < 15.0
    }

    // MARK: - CodeX 状态感知
    private func isCodeXActive() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else { return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let todayDir = sessionsDir.appendingPathComponent(formatter.string(from: Date()))

        var targetFiles: [URL] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: todayDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            targetFiles.append(contentsOf: files.filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" })
        }

        if targetFiles.isEmpty {
            if let enumerator = FileManager.default.enumerator(
                at: sessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    if url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
                        targetFiles.append(url)
                    }
                }
            }
        }

        var latestFile: URL?
        var latestDate: Date = .distantPast
        for file in targetFiles {
            if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let mdate = attrs.contentModificationDate,
               mdate > latestDate {
                latestDate = mdate
                latestFile = file
            }
        }

        guard let file = latestFile else { return false }
        let age = Date().timeIntervalSince(latestDate)
        if age > 45.0 { return false }

        guard let tail = readTail(of: file.path, maxBytes: 16384) else { return false }
        let lines = tail.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let lastLine = lines.last,
              let data = lastLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let payload = json["payload"] as? [String: Any],
           let pType = payload["type"] as? String {
            if pType == "task_complete" {
                return false
            }
        }
        return true
    }

    // MARK: - Claude Code 状态感知
    private func isClaudeCodeActive() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return false }

        guard let projectFolders = try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return false }

        var latestFile: URL?
        var latestDate: Date = .distantPast

        for folder in projectFolders {
            if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for file in files where file.pathExtension == "jsonl" {
                    if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                       let mdate = attrs.contentModificationDate,
                       mdate > latestDate {
                        latestDate = mdate
                        latestFile = file
                    }
                }
            }
        }

        guard let file = latestFile else { return false }
        let age = Date().timeIntervalSince(latestDate)
        if age > 30.0 { return false }

        guard let tail = readTail(of: file.path, maxBytes: 16384) else { return false }
        let lines = tail.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String
            if type == "assistant" {
                let msg = json["message"] as? [String: Any]
                let stopReason = (msg?["stop_reason"] as? String) ?? (json["stop_reason"] as? String)
                if stopReason == "end_turn" || stopReason == "stop_sequence" {
                    return false
                } else if stopReason == "tool_use" {
                    return true
                }
            } else if type == "user" || type == "queue-operation" {
                return true
            }
        }
        return false
    }

    // MARK: - 文件尾部高效读取工具
    private func readTail(of path: String, maxBytes: Int = 65536) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        guard fileSize > 0 else { return nil }
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        do {
            try fileHandle.seek(toOffset: offset)
            let data = fileHandle.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
