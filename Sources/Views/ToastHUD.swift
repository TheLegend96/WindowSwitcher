import SwiftUI
import AppKit

@MainActor
public class ToastHUDController {
    public static let shared = ToastHUDController()

    private var toastWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    @MainActor
    public func showToast(
        message: String,
        icon: String = "doc.on.doc.fill",
        on screen: NSScreen? = nil
    ) {
        dismissTimer?.invalidate()
        toastWindow?.close()
        toastWindow = nil

        let targetScreen = screen ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let accentColor = SettingsManager.shared.accentColor
        let rootView = ToastView(icon: icon, message: message, accentColor: accentColor)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 44)
        panel.contentView = hostingView

        // Position at bottom center of the active target screen
        let screenRect = targetScreen.frame
        let toastWidth: CGFloat = 360
        let toastHeight: CGFloat = 44
        let posX = screenRect.origin.x + (screenRect.width - toastWidth) / 2
        let posY = screenRect.origin.y + 64 // 64px above Dock / bottom

        panel.setFrame(NSRect(x: posX, y: posY, width: toastWidth, height: toastHeight), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        // Smooth fade-in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1.0
        }

        self.toastWindow = panel

        // Auto-dismiss after 1.8s
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    @MainActor
    public func dismiss() {
        guard let panel = toastWindow else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.toastWindow?.close()
                self?.toastWindow = nil
            }
        })
    }
}

private struct ToastView: View {
    let icon: String
    let message: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accentColor)

            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
