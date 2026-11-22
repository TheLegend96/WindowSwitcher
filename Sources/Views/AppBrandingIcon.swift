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
