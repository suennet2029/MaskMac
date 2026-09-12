import SwiftUI
import AppKit

@MainActor
final class TopRunnerWindow: NSPanel {
    static let shared = TopRunnerWindow()

    private init() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let menuBarHeight: CGFloat = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
        let actualMBHeight = max(24, menuBarHeight)
        let runnerHeight: CGFloat = 16
        let y = screen.frame.height - actualMBHeight - runnerHeight + 2

        super.init(
            contentRect: NSRect(x: 0, y: y, width: screen.frame.width, height: runnerHeight),
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

        let view = TopRunnerContentView()
        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let menuBarHeight: CGFloat = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
        let actualMBHeight = max(24, menuBarHeight)
        let runnerHeight: CGFloat = 16
        let y = screen.frame.height - actualMBHeight - runnerHeight + 2
        self.setFrame(NSRect(x: 0, y: y, width: screen.frame.width, height: runnerHeight), display: true)

        self.alphaValue = 0
        self.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            self.animator().alphaValue = 1.0
        }
    }

    func hide() {
        guard self.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
            }
        })
    }
}

struct TopRunnerContentView: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((elapsed * 380).truncatingRemainder(dividingBy: Double(width)))

                ZStack(alignment: .top) {
                    // 底层柔和霓虹漫射光晕 (弥散感)
                    HStack(spacing: 0) {
                        LinearGradient(
                            colors: [.cyan, .purple, .pink, .orange, .cyan, .purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 2)
                        .offset(x: -phase)
                    }
                    .frame(height: 8)
                    .blur(radius: 5)
                    .opacity(0.85)

                    // 核心激光高亮流光条 (3.5px 极亮核心)
                    HStack(spacing: 0) {
                        LinearGradient(
                            colors: [.cyan, .purple, .pink, .orange, .cyan, .purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 2)
                        .offset(x: -phase)
                    }
                    .frame(height: 3.5)
                    .shadow(color: .white.opacity(0.7), radius: 2)
                }
            }
        }
        .ignoresSafeArea()
    }
}
