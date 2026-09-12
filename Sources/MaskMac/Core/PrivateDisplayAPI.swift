import CoreGraphics
import Darwin

@MainActor
enum PrivateDisplayAPI {
    /// 私有 API：启用或注销指定显示器通道（等效于硬件注销/接入，触发桌面自动重排）
    typealias ConfigureDisplayEnabled = @convention(c) (
        OpaquePointer?,
        CGDirectDisplayID,
        Bool
    ) -> CGError

    /// 私有 API：读取显示器背光亮度 (DisplayServices)
    typealias DisplayServicesGetBrightnessFunc = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32

    /// 私有 API：设置显示器背光亮度 (DisplayServices)
    typealias DisplayServicesSetBrightnessFunc = @convention(c) (
        CGDirectDisplayID,
        Float
    ) -> Int32

    private static let coreGraphicsHandle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY
    )
    private static let skyLightHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )
    private static let displayServicesHandle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    /// 动态绑定 CGSConfigureDisplayEnabled / SLSConfigureDisplayEnabled
    static let configureDisplayEnabled: ConfigureDisplayEnabled? = {
        let candidates: [(UnsafeMutableRawPointer?, String)] = [
            (coreGraphicsHandle, "CGSConfigureDisplayEnabled"),
            (skyLightHandle, "CGSConfigureDisplayEnabled"),
            (skyLightHandle, "SLSConfigureDisplayEnabled")
        ]
        for (handle, symbolName) in candidates {
            guard let symbol = dlsym(handle, symbolName) else { continue }
            return unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self)
        }
        return nil
    }()

    private static let getBrightnessFunc: DisplayServicesGetBrightnessFunc? = {
        guard let handle = displayServicesHandle,
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: DisplayServicesGetBrightnessFunc.self)
    }()

    private static let setBrightnessFunc: DisplayServicesSetBrightnessFunc? = {
        guard let handle = displayServicesHandle,
              let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: DisplayServicesSetBrightnessFunc.self)
    }()

    /// 读取指定屏幕亮度 (0.0 - 1.0)
    static func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
        guard let fn = getBrightnessFunc else { return nil }
        var brightness: Float = 0
        let result = fn(displayID, &brightness)
        guard result == 0 else { return nil }
        return brightness
    }

    /// 设置指定屏幕亮度 (0.0 - 1.0)
    static func setBrightness(for displayID: CGDirectDisplayID, brightness: Float) -> Bool {
        guard let fn = setBrightnessFunc else { return false }
        let clamped = max(0.0, min(1.0, brightness))
        return fn(displayID, clamped) == 0
    }
}
