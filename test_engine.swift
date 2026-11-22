import Cocoa
import CoreGraphics
import ApplicationServices
import ScreenCaptureKit

@main
struct TestEngine {
    static func main() async {
        print("=== MAC WINDOW SWITCHER - CORE ENGINE TEST (Apple Silicon & ScreenCaptureKit) ===")

        // 1. Check Permissions
        let isAccessibilityTrusted = AXIsProcessTrusted()
        print("1. Accessibility Permission:", isAccessibilityTrusted ? "GRANTED" : "NOT GRANTED")

        let isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        print("2. Screen Recording Permission:", isScreenRecordingGranted ? "GRANTED" : "NOT GRANTED")

        // 2. Fetch Shareable Content using ScreenCaptureKit
        print("\n3. Querying SCShareableContent...")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("Total SCWindows returned: \(content.windows.count)")
            print("Total Applications: \(content.applications.count)")

            // Filter standard windows
            // Normal app windows usually have layer == 0, reasonable dimensions, and non-empty app name
            let candidateWindows = content.windows.filter { window in
                guard window.isOnScreen,
                      window.windowLayer == 0,
                      window.frame.width > 100,
                      window.frame.height > 100,
                      let app = window.owningApplication,
                      !app.applicationName.isEmpty
                else { return false }
                return true
            }

            print("\nFound \(candidateWindows.count) candidate windows for switcher:")
            for (idx, w) in candidateWindows.prefix(15).enumerated() {
                let appName = w.owningApplication?.applicationName ?? "Unknown"
                let title = w.title ?? "(No Title)"
                print("  [\(idx)] App: \(appName.padding(toLength: 20, withPad: " ", startingAt: 0)) | PID: \(w.owningApplication?.processID ?? 0) | ID: \(w.windowID) | Size: \(Int(w.frame.width))x\(Int(w.frame.height)) | Title: \"\(title)\"")
            }

            // 4. Test Thumbnail Capture using SCScreenshotManager
            if let firstWindow = candidateWindows.first {
                print("\n4. Capturing thumbnail with SCScreenshotManager for window \(firstWindow.windowID) (\(firstWindow.owningApplication?.applicationName ?? "")...")
                let filter = SCContentFilter(desktopIndependentWindow: firstWindow)
                let config = SCStreamConfiguration()
                // Capture at 1/2 or thumbnail resolution for blazing fast performance
                let targetWidth = min(Int(firstWindow.frame.width), 800)
                let targetHeight = Int(Double(targetWidth) * Double(firstWindow.frame.height) / Double(firstWindow.frame.width))
                config.width = targetWidth
                config.height = targetHeight
                config.scalesToFit = true
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
                let outputPath = "/tmp/switcher_sc_thumbnail.png"
                if let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try pngData.write(to: URL(fileURLWithPath: outputPath))
                    print("✅ Successfully captured hardware-accelerated thumbnail! Saved to \(outputPath) (\(pngData.count) bytes)")
                }
            }
        } catch {
            print("❌ ScreenCaptureKit Error: \(error.localizedDescription)")
            print("Note: Screen Recording permission may need to be enabled for Terminal / Antigravity in System Settings.")
        }

        print("\n=== ENGINE TEST FINISHED ===")
    }
}
