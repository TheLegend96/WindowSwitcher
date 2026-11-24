import SwiftUI
import AppKit

@MainActor
public class ToastHUDController {
    public static let shared = ToastHUDController()

    private var toastWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    /// Shows the interactive liquid glass OCR toast notification with live text preview and Cut Breaks action.
    public func showOCRToast(
        text: String,
        on screen: NSScreen? = nil
    ) {
        dismissTimer?.invalidate()
        toastWindow?.close()
        toastWindow = nil

        let targetScreen = screen ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        let panelW: CGFloat = 400
        let panelH: CGFloat = 68

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false

        let accentColor = SettingsManager.shared.accentColor
        let model = OCRToastModel(
            text: text,
            onCutBreaks: { newText in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(newText, forType: .string)
                NSSound.beep()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let rootView = OCRToastView(model: model, accentColor: accentColor)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        panel.contentView = hostingView

        // Position at bottom center of the active target screen
        let screenRect = targetScreen.frame
        let posX = screenRect.origin.x + (screenRect.width - panelW) / 2
        let posY = screenRect.origin.y + 60

        panel.setFrame(NSRect(x: posX, y: posY, width: panelW, height: panelH), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        // Smooth spring fade-in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            panel.animator().alphaValue = 1.0
        }

        self.toastWindow = panel

        // 4.5s auto-dismiss timer giving users ample time to click Cut Breaks
        scheduleDismissTimer(duration: 4.5)
    }

    /// Shows a standard simple status message (e.g. for errors or empty selections).
    public func showSimpleToast(
        message: String,
        icon: String = "info.circle",
        on screen: NSScreen? = nil
    ) {
        dismissTimer?.invalidate()
        toastWindow?.close()
        toastWindow = nil

        let targetScreen = screen ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        let panelW: CGFloat = 320
        let panelH: CGFloat = 44

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false

        let accentColor = SettingsManager.shared.accentColor
        let rootView = SimpleToastView(message: message, icon: icon, accentColor: accentColor)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        panel.contentView = hostingView

        let screenRect = targetScreen.frame
        let posX = screenRect.origin.x + (screenRect.width - panelW) / 2
        let posY = screenRect.origin.y + 60

        panel.setFrame(NSRect(x: posX, y: posY, width: panelW, height: panelH), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1.0
        }

        self.toastWindow = panel
        scheduleDismissTimer(duration: 2.2)
    }

    private func scheduleDismissTimer(duration: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

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

// MARK: - Interactive OCR Observable Model
final class OCRToastModel: ObservableObject {
    @Published var currentText: String
    @Published var breaksCut: Bool = false
    let originalText: String
    let onCutBreaks: (String) -> Void
    let onDismiss: () -> Void

    init(text: String, onCutBreaks: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.currentText = text
        self.originalText = text
        self.onCutBreaks = onCutBreaks
        self.onDismiss = onDismiss
    }

    func toggleCutBreaks() {
        if !breaksCut {
            let singleLine = originalText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            currentText = singleLine
            breaksCut = true
            onCutBreaks(singleLine)
        } else {
            currentText = originalText
            breaksCut = false
            onCutBreaks(originalText)
        }
    }
}

// MARK: - Interactive OCR Liquid Glass Toast View
private struct OCRToastView: View {
    @ObservedObject var model: OCRToastModel
    let accentColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // App Branding Icon
            AppBrandingIcon(size: 32, cornerRadius: 7.5)

            // Text Content (Title + Clean 2-Line Snippet)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.breaksCut ? "Text formatted & copied" : "Text copied to the clipboard")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)

                Text(previewSnippet)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)
            }

            Spacer(minLength: 4)

            // "Cut Breaks" Button
            Button(action: { model.toggleCutBreaks() }) {
                HStack(spacing: 4) {
                    if model.breaksCut {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    Text(model.breaksCut ? "Breaks Cut" : "Cut Breaks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(model.breaksCut ? .green : .primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.breaksCut ? Color.green.opacity(0.12) : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(model.breaksCut ? Color.green.opacity(0.35) : Color.primary.opacity(0.12), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            // Dismiss X Button
            Button(action: model.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 5)
    }

    private var previewSnippet: String {
        let trimmed = model.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty selection" : trimmed
    }
}

// MARK: - Simple Status Toast View
private struct SimpleToastView: View {
    let message: String
    let icon: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accentColor)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
    }
}
