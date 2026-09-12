import SwiftUI
import AppKit

@MainActor
final class ScreenAuraWindow: NSPanel {
    static let shared = ScreenAuraWindow()

    private init() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = true

        let view = AppleIntelligenceAuraView()
        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        self.setFrame(screen.frame, display: true)

        self.alphaValue = 0
        self.orderFront(nil)

        // 像呼吸一样自然柔和地点亮
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    func hide() {
        guard self.isVisible else { return }
        // 任务完成后柔和暗下并彻底消失
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
            }
        })
    }
}

struct AppleIntelligenceAuraView: View {
    // 苹果 Apple Intelligence 标志性全光谱流光色系
    private let auraColors: [Color] = [
        Color(red: 0.05, green: 0.55, blue: 1.0),   // Electric Blue
        Color(red: 0.1,  green: 0.9,  blue: 0.95),  // Vivid Cyan
        Color(red: 0.65, green: 0.2,  blue: 0.98),  // Neon Violet
        Color(red: 0.98, green: 0.25, blue: 0.65),  // Hot Magenta
        Color(red: 1.0,  green: 0.6,  blue: 0.2),   // Amber Gold
        Color(red: 0.05, green: 0.55, blue: 1.0)    // Loop back
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            // 1. 全屏边框光斑旋转角度
            let angle = (t * 85).truncatingRemainder(dividingBy: 360)

            // 2. 核心：自然生动的“微微闪烁与呼吸”
            // 组合低频深呼吸 (2.2 rad/s) 与微闪光波 (7.5 rad/s)
            let slowBreath = (sin(t * 2.2) + 1.0) / 2.0
            let microShimmer = (sin(t * 7.5) + 1.0) / 2.0
            let shimmerOpacity = 0.62 + (slowBreath * 0.28) + (microShimmer * 0.10) // 0.62 ~ 1.0 呼吸微闪
            let glowRadius = CGFloat(8.0 + slowBreath * 10.0 + microShimmer * 4.0)   // 8 ~ 22px 动态弥散
            let coreWidth = CGFloat(2.8 + slowBreath * 1.4)                         // 2.8 ~ 4.2px

            let gradient = AngularGradient(
                colors: auraColors,
                center: .center,
                startAngle: .degrees(angle),
                endAngle: .degrees(angle + 360)
            )

            ZStack {
                // 外层深层大漫射微光光晕 (Apple Intelligence 氛围感)
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(gradient, lineWidth: 16)
                    .blur(radius: glowRadius)
                    .opacity(shimmerOpacity * 0.75)

                // 中层高斯弥散霓虹边框
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(gradient, lineWidth: 8)
                    .blur(radius: glowRadius * 0.45)
                    .opacity(shimmerOpacity * 0.9)

                // 核心极亮微光流转条 (呼吸闪烁)
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(gradient, lineWidth: coreWidth)
                    .shadow(color: .white.opacity(shimmerOpacity * 0.8), radius: 3)
                    .opacity(shimmerOpacity)
            }
            .padding(2)
        }
        .ignoresSafeArea()
    }
}
