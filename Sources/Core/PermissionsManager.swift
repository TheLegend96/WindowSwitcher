import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

public class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public var hasAccessibility: Bool = false
    @Published public var hasScreenRecording: Bool = false

    private init() {
        checkPermissions()
    }

    private var lastTrusted: Bool?
    private var lastScreen: Bool?

    public func checkPermissions() {
        let trusted = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        
        let changed = (lastTrusted != trusted || lastScreen != screen)
        if changed {
            hasAccessibility = trusted
            hasScreenRecording = screen
            lastTrusted = trusted
            lastScreen = screen
            print("🔍 Permissions Status Changed: Accessibility=\(trusted), ScreenRecording=\(screen), isListening=\(EventTapManager.shared.isListening)")
        }

        if trusted && !EventTapManager.shared.isListening {
            EventTapManager.shared.start()
        }
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibility = trusted
        print("Requested Accessibility, result: \(trusted)")
        if !trusted {
            openSystemSettings(pane: "Privacy_Accessibility")
        } else {
            EventTapManager.shared.start()
        }
    }

    public func requestScreenRecording() {
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await MainActor.run {
                self.checkPermissions()
            }
        }
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecording = granted
        print("Requested Screen Recording, result: \(granted)")
        if !granted {
            openSystemSettings(pane: "Privacy_ScreenCapture")
        }
    }

    public func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
