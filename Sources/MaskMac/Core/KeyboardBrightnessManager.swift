import Foundation
import ObjectiveC

@MainActor
final class KeyboardBrightnessManager {
    static let shared = KeyboardBrightnessManager()

    private var client: AnyObject?
    private var copyIDsSel: Selector
    private var brightnessSel: Selector
    private var setBrightnessSel: Selector
    private var keyboardIDs: [UInt64] = []

    // 呼吸灯动画状态
    private var breathingTimer: Timer?
    private var savedBrightnessBeforeBreathing: Float?
    private var breathingStep: Double = 0
    private(set) var isBreathing: Bool = false

    typealias CopyIDsFunc = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    typealias BrightnessFunc = @convention(c) (AnyObject, Selector, UInt64) -> Float
    typealias SetBrightnessFunc = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private var copyIDsImpl: CopyIDsFunc?
    private var getBrightnessImpl: BrightnessFunc?
    private var setBrightnessImpl: SetBrightnessFunc?

    private init() {
        copyIDsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        brightnessSel = NSSelectorFromString("brightnessForKeyboard:")
        setBrightnessSel = NSSelectorFromString("setBrightness:forKeyboard:")

        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              bundle.load(),
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            NSLog("MaskMac: CoreBrightness or KeyboardBrightnessClient unavailable")
            return
        }

        let instance = cls.init()
        self.client = instance

        if instance.responds(to: copyIDsSel) {
            copyIDsImpl = unsafeBitCast(instance.method(for: copyIDsSel), to: CopyIDsFunc.self)
        }
        if instance.responds(to: brightnessSel) {
            getBrightnessImpl = unsafeBitCast(instance.method(for: brightnessSel), to: BrightnessFunc.self)
        }
        if instance.responds(to: setBrightnessSel) {
            setBrightnessImpl = unsafeBitCast(instance.method(for: setBrightnessSel), to: SetBrightnessFunc.self)
        }

        refreshKeyboardIDs()
    }

    func refreshKeyboardIDs() {
        guard let client, let copyIDsImpl else { return }
        if let idsUnmanaged = copyIDsImpl(client, copyIDsSel) {
            let ids = idsUnmanaged.takeRetainedValue() as? [UInt64] ?? []
            self.keyboardIDs = ids
        }
    }

    /// 当前键盘背光亮度 (0.0 ~ 1.0)
    var brightness: Float {
        get {
            guard let client, let getBrightnessImpl, let kid = keyboardIDs.first else {
                return 0.0
            }
            return getBrightnessImpl(client, brightnessSel, kid)
        }
        set {
            setBrightness(newValue)
        }
    }

    /// 设置键盘背光亮度 (0.0 ~ 1.0)
    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard let client, let setBrightnessImpl, !keyboardIDs.isEmpty else {
            return false
        }
        let clamped = max(0.0, min(1.0, value))
        var success = true
        for kid in keyboardIDs {
            let res = setBrightnessImpl(client, setBrightnessSel, clamped, kid)
            if !res { success = false }
        }
        return success
    }

    /// 开始键盘背光呼吸动效（大模型运行状态）
    func startBreathing() {
        guard !isBreathing else { return }
        savedBrightnessBeforeBreathing = brightness
        isBreathing = true
        breathingStep = 0

        breathingTimer?.invalidate()
        breathingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isBreathing else { return }
                self.breathingStep += 0.1
                // 正弦波产生 0.1 ~ 0.8 之间的平滑呼吸亮度
                let wave = (sin(self.breathingStep) + 1.0) / 2.0 // 0.0 ~ 1.0
                let targetBrightness = Float(0.08 + wave * 0.72)
                self.setBrightness(targetBrightness)
            }
        }
    }

    /// 停止键盘背光呼吸动效，并恢复之前亮度
    func stopBreathing() {
        guard isBreathing else { return }
        isBreathing = false
        breathingTimer?.invalidate()
        breathingTimer = nil

        if let original = savedBrightnessBeforeBreathing {
            setBrightness(original)
            savedBrightnessBeforeBreathing = nil
        }
    }
}
