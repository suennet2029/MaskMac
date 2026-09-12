import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

@MainActor
final class KeyboardLEDManager {
    static let shared = KeyboardLEDManager()

    typealias SetLockFunc = @convention(c) (io_connect_t, Int32, Bool) -> kern_return_t
    typealias GetLockFunc = @convention(c) (io_connect_t, Int32, UnsafeMutablePointer<DarwinBoolean>) -> kern_return_t

    private var setLockFunc: SetLockFunc?
    private var getLockFunc: GetLockFunc?
    private var ioConnect: io_connect_t = 0
    private var isConnected: Bool = false

    private var blinkTimer: Timer?
    private var isLEDOn: Bool = false
    private var savedInitialState: Bool = false
    private(set) var isBlinking: Bool = false

    private init() {
        setupModifierLock()
    }

    private func setupModifierLock() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        if let handle = handle,
           let symSet = dlsym(handle, "IOHIDSetModifierLockState"),
           let symGet = dlsym(handle, "IOHIDGetModifierLockState") {
            setLockFunc = unsafeBitCast(symSet, to: SetLockFunc.self)
            getLockFunc = unsafeBitCast(symGet, to: GetLockFunc.self)
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else {
            NSLog("MaskMac: IOHIDSystem service not found")
            return
        }
        let kr = IOServiceOpen(service, mach_task_self_, 1, &ioConnect)
        if kr == KERN_SUCCESS {
            isConnected = true
        } else {
            NSLog("MaskMac: IOServiceOpen failed kr=\(kr)")
        }
    }

    /// 获取当前 Caps Lock / 中英键锁定状态
    var isLocked: Bool {
        guard isConnected, let getLockFunc else { return false }
        var state: DarwinBoolean = false
        _ = getLockFunc(ioConnect, 1, &state)
        return state.boolValue
    }

    /// 设置键盘 CapsLock / 中英键指示灯硬件状态
    func setLED(on: Bool) {
        guard isConnected, let setLockFunc else { return }
        isLEDOn = on
        _ = setLockFunc(ioConnect, 1, on)
    }

    /// 开始闪烁中/英键指示灯
    func startBlinking(interval: TimeInterval = 0.35) {
        guard !isBlinking else { return }
        isBlinking = true
        savedInitialState = isLocked

        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isBlinking else { return }
                self.setLED(on: !self.isLEDOn)
            }
        }
    }

    /// 停止闪烁，并恢复初始状态或关闭
    func stopBlinking() {
        guard isBlinking else { return }
        isBlinking = false
        blinkTimer?.invalidate()
        blinkTimer = nil
        setLED(on: false)
    }
}
