import Foundation

func testBrightnessClamping() {
    func clamp(_ value: Float) -> Float {
        return max(0.0, min(1.0, value))
    }
    precondition(clamp(-0.5) == 0.0, "Negative brightness should clamp to 0.0")
    precondition(clamp(1.5) == 1.0, "Excessive brightness should clamp to 1.0")
    precondition(clamp(0.7) == 0.7, "Valid brightness should remain 0.7")
}

@main
struct BrightnessAndLLMTests {
    static func main() {
        testBrightnessClamping()
        print("Passed all Brightness tests successfully.")
    }
}
