import AppKit
import ScreenCaptureKit

public class ThumbnailManager {
    public static let shared = ThumbnailManager()
    private let cache = NSCache<NSNumber, NSImage>()

    private init() {
        cache.countLimit = 60
    }

    public func getCachedThumbnail(for windowID: CGWindowID) -> NSImage? {
        return cache.object(forKey: NSNumber(value: windowID))
    }

    public func captureThumbnail(for window: SwitcherWindow, forceRefresh: Bool = true) async -> NSImage? {
        if !forceRefresh, let cached = cache.object(forKey: NSNumber(value: window.id)) {
            return cached
        }

        var targetSCWindow = window.scWindow

        // If scWindow is not yet attached or invalid, look it up in SCShareableContent
        if targetSCWindow == nil || (targetSCWindow?.frame.width ?? 0) < 50 {
            if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
                targetSCWindow = content.windows.first(where: { $0.windowID == window.id })
                window.scWindow = targetSCWindow
            }
        }

        guard let scWindow = targetSCWindow else { return nil }

        // Guard against zero-sized or invalid frames to avoid ScreenCaptureKit assertion failures
        guard scWindow.frame.width >= 50 && scWindow.frame.height >= 50 else { return nil }

        do {
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()

            let winW = max(Int(scWindow.frame.width), 100)
            let winH = max(Int(scWindow.frame.height), 100)

            // High-speed proportional thumbnail capture optimized for HUD card display (Retina 2x @ 110pt)
            let maxDim: CGFloat = 360
            let scale = min(maxDim / CGFloat(winW), maxDim / CGFloat(winH), 1.0)
            let targetW = max(Int(CGFloat(winW) * scale), 100)
            let targetH = max(Int(CGFloat(winH) * scale), 100)

            config.width = targetW
            config.height = targetH
            config.scalesToFit = true
            config.showsCursor = false
            config.capturesAudio = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: targetW, height: targetH))

            cache.setObject(nsImage, forKey: NSNumber(value: window.id))
            return nsImage
        } catch {
            return nil
        }
    }

    public func clearCache() {
        cache.removeAllObjects()
    }
}
