import SwiftUI
import AppKit

public struct AppBrandingIcon: View {
    public var size: CGFloat
    public var cornerRadius: CGFloat

    public init(size: CGFloat = 34, cornerRadius: CGFloat = 8) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    private var loadedIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon-CobaltAzure", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let fallbackPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: fallbackPath) {
            return img
        }
        let fallbackFile = "/Users/pruthvirajmane/.gemini/antigravity/scratch/mac-window-switcher/Resources/AppIcon-CobaltAzure.png"
        if FileManager.default.fileExists(atPath: fallbackFile),
           let img = NSImage(contentsOfFile: fallbackFile) {
            return img
        }
        return NSApp.applicationIconImage
    }

    public var body: some View {
        if let img = loadedIcon {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.20), radius: max(2, size * 0.08), x: 0, y: max(1, size * 0.04))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.blue)
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

public struct NativeAppIconView: View {
    public let bundleId: String
    public let size: CGFloat

    public init(bundleId: String, size: CGFloat = 32) {
        self.bundleId = bundleId
        self.size = size
    }

    private var appIcon: NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first, let icon = app.icon {
            return icon
        }
        if bundleId == "com.apple.finder" {
            let path = "/System/Library/CoreServices/Finder.app"
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        if bundleId == "com.apple.ScreenSharing" {
            let path = "/System/Applications/Utilities/Screen Sharing.app"
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }

    public var body: some View {
        if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(.secondary)
        }
    }
}
