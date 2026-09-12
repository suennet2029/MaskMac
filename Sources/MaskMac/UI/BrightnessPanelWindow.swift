import AppKit
import SwiftUI

@MainActor
final class BrightnessPanelWindow: NSPanel {
    static let shared = BrightnessPanelWindow()

    private var localMouseDownMonitor: Any?

    private init() {
        let contentRect = NSRect(x: 0, y: 0, width: 250, height: 95)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: BrightnessContentView())
        self.contentView = hosting
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if self.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))

        let panelWidth: CGFloat = 250
        let panelHeight: CGFloat = 95

        // 核心：严格计算在状态栏下方，留出 6pt 呼吸空隙，绝不遮挡顶部菜单栏按钮
        let y = buttonFrame.minY - panelHeight - 6

        // 水平居中对齐图标，并限制在屏幕可视区域内
        var x = buttonFrame.midX - panelWidth / 2
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - panelWidth - 8
        x = max(minX, min(x, maxX))

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        self.orderFront(nil)

        // 监听点击外部自动关闭
        startOutsideClickMonitor()
    }

    func hide() {
        stopOutsideClickMonitor()
        self.orderOut(nil)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let clickLocation = NSEvent.mouseLocation
            if !self.frame.contains(clickLocation) {
                self.hide()
            }
            return event
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = localMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseDownMonitor = nil
        }
    }
}

struct BrightnessContentView: View {
    @State private var screenBrightness: Double = 0.8
    @State private var keyboardBrightness: Double = 0.5

    var body: some View {
        VStack(spacing: 12) {
            // 屏幕亮度滑动条
            HStack(spacing: 8) {
                Image(systemName: "sun.min.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))

                Slider(value: $screenBrightness, in: 0.0...1.0)
                    .onChange(of: screenBrightness) { _, newValue in
                        PrivateDisplayAPI.setCurrentDisplayBrightness(Float(newValue))
                    }

                Image(systemName: "sun.max.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                Text("\(Int(screenBrightness * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            // 原生键盘背光滑动条
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))

                Slider(value: $keyboardBrightness, in: 0.0...1.0)
                    .onChange(of: keyboardBrightness) { _, newValue in
                        KeyboardBrightnessManager.shared.setBrightness(Float(newValue))
                    }

                Image(systemName: "keyboard.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                Text("\(Int(keyboardBrightness * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
        )
        .frame(width: 250, height: 95)
        .onAppear {
            let s = Double(PrivateDisplayAPI.getCurrentDisplayBrightness())
            if s > 0 { screenBrightness = s }
            keyboardBrightness = Double(KeyboardBrightnessManager.shared.brightness)
        }
    }
}
