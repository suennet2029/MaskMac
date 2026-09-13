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
}
