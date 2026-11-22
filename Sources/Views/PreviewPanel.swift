import Cocoa
import ScreenCaptureKit
import CoreMedia
import VideoToolbox

final class LiveStreamDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    weak var panel: PreviewPanel?

    init(panel: PreviewPanel) {
        self.panel = panel
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard status == noErr, let img = cgImage else { return }

        DispatchQueue.main.async { [weak self] in
            self?.panel?.handleLiveFrame(img)
        }
    }
}

@MainActor
public class PreviewPanel: NSPanel {
    public static let shared = PreviewPanel()

    // Dual-layer hierarchy to eliminate rectangular shadow clipping artifacts
    private let shadowMargin: CGFloat = 36
    private let shadowHostView = NSView()
    private let containerView = NSView()

    private let visualEffect = NSVisualEffectView()
    private let imageView = NSImageView()
    private let liveLayer = CALayer()
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let fallbackView = NSView()
    private let borderLayer = CALayer()

    private var currentWindowID: CGWindowID?
    private var activeStreamWindowID: CGWindowID?
    private weak var currentTargetWindow: SwitcherWindow?

    private var activeStream: SCStream?
    private var streamTask: Task<Void, Never>?
    private var streamDelegate: LiveStreamDelegate?
    private var frameCounter: Int = 0

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // One level below Switcher HUD so HUD floats on top of live mirror
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear

        // Disable WindowServer default rectangular window shadow.
        // We render an authentic Apple rounded-geometry shadow using CoreAnimation shadowPath.
        self.hasShadow = false
        self.ignoresMouseEvents = true

        setupViews()
    }

    private func setupViews() {
        // 1. Outer Shadow Host (unclipped, allows smooth Gaussian shadow falloff)
        shadowHostView.wantsLayer = true
        shadowHostView.layer?.masksToBounds = false
        shadowHostView.layer?.shadowColor = NSColor.black.cgColor
        shadowHostView.layer?.shadowOpacity = 0.52
        shadowHostView.layer?.shadowRadius = 28
        shadowHostView.layer?.shadowOffset = CGSize(width: 0, height: -12)

        // 2. Inner Content Container (cleanly clipped to 16px Apple squircle)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 16
        containerView.layer?.masksToBounds = true

        // 3. Frosted Backdrop
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        visualEffect.autoresizingMask = [.width, .height]
        containerView.addSubview(visualEffect)

        // 4. Instant Thumbnail Fallback View (0ms latency display)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        containerView.addSubview(imageView)

        // 5. Real-time Live Screen Recording Stream Display Layer (Hardware accelerated)
        liveLayer.cornerRadius = 16
        liveLayer.masksToBounds = true
        liveLayer.contentsGravity = .resize
        containerView.layer?.addSublayer(liveLayer)

        // 6. Fallback View for icon-only windows
        fallbackView.wantsLayer = true
        fallbackView.autoresizingMask = [.width, .height]
        fallbackView.isHidden = true

        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackView.addSubview(iconImageView)

        titleLabel.alignment = .center
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        fallbackView.addSubview(titleLabel)

        containerView.addSubview(fallbackView)

        // 7. Specular Accent Selection Border Layer
        borderLayer.cornerRadius = 16
        borderLayer.borderWidth = 3.0
        borderLayer.borderColor = NSColor(red: 0.05, green: 0.50, blue: 1.0, alpha: 0.95).cgColor
        borderLayer.masksToBounds = true
        containerView.layer?.addSublayer(borderLayer)

        shadowHostView.addSubview(containerView)
        self.contentView = shadowHostView
    }

    private func updateLayout(contentSize: NSSize) {
        let totalW = contentSize.width + shadowMargin * 2
        let totalH = contentSize.height + shadowMargin * 2

        shadowHostView.frame = NSRect(x: 0, y: 0, width: totalW, height: totalH)

        let innerRect = NSRect(
            x: shadowMargin,
            y: shadowMargin,
            width: contentSize.width,
            height: contentSize.height
        )
        containerView.frame = innerRect

        // Pixel-perfect CoreAnimation shadow geometry: strictly follows the 16px rounded window
        let path = CGPath(roundedRect: innerRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        shadowHostView.layer?.shadowPath = path

        visualEffect.frame = containerView.bounds
        imageView.frame = containerView.bounds
        liveLayer.frame = containerView.bounds
        fallbackView.frame = containerView.bounds
        borderLayer.frame = containerView.bounds

        // Update border color dynamically if custom accent is set
        let accentHex = SettingsManager.shared.customAccentColorHex
        if let customCol = NSColor(hex: accentHex) {
            borderLayer.borderColor = customCol.cgColor
        }

        let iconSize: CGFloat = 96
        iconImageView.frame = NSRect(
            x: (contentSize.width - iconSize) / 2,
            y: (contentSize.height - iconSize) / 2 + 16,
            width: iconSize,
            height: iconSize
        )

        titleLabel.frame = NSRect(
            x: 20,
            y: (contentSize.height - iconSize) / 2 - 32,
            width: contentSize.width - 40,
            height: 30
        )
    }

    public func show(for window: SwitcherWindow, relativeTo overlayWindowNumber: Int) {
        guard let primaryScreen = NSScreen.screens.first else { return }

        let screenH = primaryScreen.frame.height
        let screenW = primaryScreen.frame.width
        let winBounds = window.bounds

        let isValidBounds = winBounds.width >= 320 && winBounds.height >= 200 && winBounds.width <= screenW * 1.5 && winBounds.height <= screenH * 1.5

        let targetContentRect: NSRect
        if !isValidBounds {
            // Minimized, off-screen, or hidden window -> Center preview at 76% screen dimensions
            let targetW = screenW * 0.76
            let targetH = screenH * 0.76
            targetContentRect = NSRect(
                x: primaryScreen.frame.midX - targetW / 2,
                y: primaryScreen.frame.midY - targetH / 2,
                width: targetW,
                height: targetH
            )
        } else {
            // Convert CoreGraphics top-left coordinates to Cocoa bottom-left coordinates
            let cocoaY = screenH - (winBounds.origin.y + winBounds.height)
            targetContentRect = NSRect(
                x: winBounds.origin.x,
                y: cocoaY,
                width: winBounds.width,
                height: winBounds.height
            )
        }

        // Expand panel frame by shadowMargin so CoreAnimation shadow renders completely unclipped
        let panelFrame = NSRect(
            x: targetContentRect.origin.x - shadowMargin,
            y: targetContentRect.origin.y - shadowMargin,
            width: targetContentRect.width + shadowMargin * 2,
            height: targetContentRect.height + shadowMargin * 2
        )

        self.setFrame(panelFrame, display: true, animate: false)
        updateLayout(contentSize: targetContentRect.size)

        self.currentTargetWindow = window
        self.currentWindowID = window.id

        // 1. Instant 0ms visual feedback: display cached thumbnail or app icon
        if let thumb = window.thumbnail ?? ThumbnailManager.shared.getCachedThumbnail(for: window.id) {
            self.imageView.image = thumb
            self.imageView.isHidden = false
            self.fallbackView.isHidden = true
        } else if let icon = window.appIcon {
            self.iconImageView.image = icon
            self.titleLabel.stringValue = window.windowTitle.isEmpty ? window.appName : window.windowTitle
            self.imageView.isHidden = true
            self.fallbackView.isHidden = false
        } else {
            self.imageView.isHidden = true
            self.fallbackView.isHidden = true
        }

        // Order the preview panel on screen directly behind the Switcher HUD
        self.orderFrontRegardless()
        if overlayWindowNumber > 0 {
            self.order(.below, relativeTo: overlayWindowNumber)
        }

        // 2. Start or update the real-time live screen recording stream
        startOrUpdateLiveStream(for: window, targetSize: targetContentRect.size)
    }

    public func update(for window: SwitcherWindow, relativeTo overlayWindowNumber: Int) {
        show(for: window, relativeTo: overlayWindowNumber)
    }

    private func createStreamConfiguration(for scWin: SCWindow) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let targetW = max(Int(scWin.frame.width * scale), 400)
        let targetH = max(Int(scWin.frame.height * scale), 300)
        config.width = targetW
        config.height = targetH
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS live recording stream
        config.showsCursor = true
        config.scalesToFit = true
        config.queueDepth = 3
        config.capturesAudio = false
        return config
    }

    private func startOrUpdateLiveStream(for window: SwitcherWindow, targetSize: NSSize) {
        streamTask?.cancel()
        streamTask = Task {
            var targetSCWindow = window.scWindow
            if targetSCWindow == nil {
                if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
                    targetSCWindow = content.windows.first(where: { $0.windowID == window.id })
                    window.scWindow = targetSCWindow
                }
            }

            guard let scWin = targetSCWindow else {
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWin)
            let config = self.createStreamConfiguration(for: scWin)

            // Dynamic filter update if stream is already actively recording
            if let existingStream = self.activeStream, self.activeStreamWindowID != nil {
                do {
                    try await existingStream.updateContentFilter(filter)
                    try await existingStream.updateConfiguration(config)
                    self.activeStreamWindowID = window.id
                    return
                } catch {
                    try? await existingStream.stopCapture()
                    self.activeStream = nil
                }
            }

            // Create and start fresh live stream
            do {
                let delegate = LiveStreamDelegate(panel: self)
                self.streamDelegate = delegate
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))
                try await stream.startCapture()
                self.activeStream = stream
                self.activeStreamWindowID = window.id
            } catch {
                // Live stream failed, thumbnail fallback handles display smoothly
            }
        }
    }

    public func handleLiveFrame(_ img: CGImage) {
        guard self.isVisible, self.currentWindowID == self.activeStreamWindowID else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.liveLayer.contents = img
        self.liveLayer.isHidden = false
        self.fallbackView.isHidden = true
        CATransaction.commit()

        // Real-time synchronization: Update the switcher card thumbnail live
        frameCounter += 1
        if frameCounter % 6 == 0, let win = currentTargetWindow, win.id == currentWindowID {
            let nsImg = NSImage(cgImage: img, size: NSSize(width: img.width / 2, height: img.height / 2))
            win.thumbnail = nsImg
        }
    }

    public func hide() {
        streamTask?.cancel()
        streamTask = nil
        currentWindowID = nil
        activeStreamWindowID = nil
        currentTargetWindow = nil

        if let stream = activeStream {
            activeStream = nil
            Task {
                try? await stream.stopCapture()
            }
        }

        self.orderOut(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.liveLayer.contents = nil
        self.liveLayer.isHidden = true
        CATransaction.commit()

        self.imageView.image = nil
        self.imageView.isHidden = true
        self.fallbackView.isHidden = true
    }
}
