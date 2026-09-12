import Foundation

func testBrightnessClamping() {
    func clamp(_ value: Float) -> Float {
        return max(0.0, min(1.0, value))
    }
    precondition(clamp(-0.5) == 0.0, "Negative brightness should clamp to 0.0")
    precondition(clamp(1.5) == 1.0, "Excessive brightness should clamp to 1.0")
    precondition(clamp(0.7) == 0.7, "Valid brightness should remain 0.7")
}

func testTargetProcessMatching() {
    func matchTarget(line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("grep") || lower.contains("maskmac") { return nil }
        if lower.contains("claude") {
            return "Claude Code"
        }
        if lower.contains("codex") {
            return "CodeX"
        }
        if lower.contains("antigravity") || lower.contains("/agy") || lower.hasPrefix("agy ") {
            return "antiGravity"
        }
        return nil
    }

    precondition(matchTarget(line: "/Users/demo/.local/share/claude/versions/2.1.90") == "Claude Code")
    precondition(matchTarget(line: "claude task start") == "Claude Code")
    precondition(matchTarget(line: "/Users/demo/.codex/packages/standalone/current/bin/codex") == "CodeX")
    precondition(matchTarget(line: "/opt/homebrew/bin/agy --agent code") == "antiGravity")
    precondition(matchTarget(line: "/Applications/Antigravity.app/Contents/MacOS/Antigravity") == "antiGravity")
    precondition(matchTarget(line: "grep claude") == nil, "grep should be ignored")
}

func testAntiGravityStateParsing() {
    func parseAntiGravity(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
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
            return false
        }
        return false
    }

    let userInput = "{\"step_index\":1,\"source\":\"USER_EXPLICIT\",\"type\":\"USER_INPUT\",\"status\":\"DONE\"}"
    let toolCall = "{\"step_index\":2,\"source\":\"MODEL\",\"type\":\"PLANNER_RESPONSE\",\"status\":\"DONE\",\"tool_calls\":[{\"name\":\"run_command\"}]}"
    let genericOutput = "{\"step_index\":3,\"source\":\"MODEL\",\"type\":\"GENERIC\",\"status\":\"DONE\"}"
    let finalAnswer = "{\"step_index\":4,\"source\":\"MODEL\",\"type\":\"PLANNER_RESPONSE\",\"status\":\"DONE\",\"content\":\"Hello world\"}"

    precondition(parseAntiGravity(line: userInput) == true, "USER_INPUT should be active")
    precondition(parseAntiGravity(line: toolCall) == true, "tool_calls should be active")
    precondition(parseAntiGravity(line: genericOutput) == true, "GENERIC tool output should be active")
    precondition(parseAntiGravity(line: finalAnswer) == false, "final response without tool_calls should be idle")
}

func testCodeXStateParsing() {
    func parseCodeX(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
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

    let completed = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"123\"}}"
    let running = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"turn_id\":\"123\"}}"

    precondition(parseCodeX(line: completed) == false, "task_complete should be idle")
    precondition(parseCodeX(line: running) == true, "item_completed should be active")
}

func testClaudeCodeStateParsing() {
    func parseClaude(lines: [String]) -> Bool {
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

    let endTurnSession = [
        "{\"type\":\"user\",\"message\":{\"role\":\"user\"}}",
        "{\"type\":\"assistant\",\"message\":{\"stop_reason\":\"end_turn\"}}",
        "{\"type\":\"last-prompt\",\"lastPrompt\":\"hi\"}"
    ]
    let activeSession = [
        "{\"type\":\"user\",\"message\":{\"role\":\"user\"}}",
        "{\"type\":\"last-prompt\",\"lastPrompt\":\"hi\"}"
    ]

    precondition(parseClaude(lines: endTurnSession) == false, "end_turn should be idle")
    precondition(parseClaude(lines: activeSession) == true, "unanswered prompt should be active")
}

@main
struct BrightnessAndLLMTests {
    static func main() {
        testBrightnessClamping()
        testTargetProcessMatching()
        testAntiGravityStateParsing()
        testCodeXStateParsing()
        testClaudeCodeStateParsing()
        print("Passed all Brightness and Agent State tests successfully.")
    }
}
