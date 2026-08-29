import CoreGraphics
import Darwin

@MainActor
enum PrivateDisplayAPI {
    typealias ConfigureDisplayEnabled = @convention(c) (
        OpaquePointer?,
        CGDirectDisplayID,
        Bool
    ) -> CGError

    private static let coreGraphicsHandle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY
    )
    private static let skyLightHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

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
}
