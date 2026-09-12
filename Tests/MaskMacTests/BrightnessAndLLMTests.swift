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

@main
struct BrightnessAndLLMTests {
    static func main() {
        testBrightnessClamping()
        testTargetProcessMatching()
        print("Passed Brightness and Agent Process tests.")
    }
}
