import SwiftUI
import AppKit

public struct WindowCardView: View {
    @ObservedObject var window: SwitcherWindow
    @ObservedObject var settings = SettingsManager.shared
    let isSelected: Bool
    let onClose: () -> Void
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    public init(
        window: SwitcherWindow,
        isSelected: Bool,
        onClose: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        onHover: @escaping (Bool) -> Void = { _ in }
    ) {
        self.window = window
        self.isSelected = isSelected
        self.onClose = onClose
        self.onSelect = onSelect
        self.onHover = onHover
    }

    // Dynamic width preserving true window proportions without cropping
    private var computedCardWidth: CGFloat {
        let size = settings.cardSize
        if settings.switcherStyle == .icons {
            return size.cardHeight * 0.95
        }
        if settings.switcherStyle == .titles {
            return 280
        }
        if let thumb = window.thumbnail {
            let w = thumb.size.width
            let h = thumb.size.height
            if w > 0 && h > 0 {
                let ratio = w / h
                let maxH: CGFloat = size.previewHeight
                let maxW: CGFloat = size.cardHeight * 1.55
                let calculatedW = min(max(maxH * ratio, 100), maxW)
                return max(calculatedW + 16, 140)
            }
        } else if window.bounds.width >= 320 && window.bounds.height >= 200 {
            // Proportional width based on window bounds even before thumbnail loads
            let ratio = window.bounds.width / window.bounds.height
            let maxH: CGFloat = size.previewHeight
            let maxW: CGFloat = size.cardHeight * 1.55
            let calculatedW = min(max(maxH * ratio, 100), maxW)
            return max(calculatedW + 16, 140)
        }
        // App icon card with no window preview (e.g. Comet, Figma, PDFgear)
        return size.iconSize + 36
    }

    public var body: some View {
        Button(action: onSelect) {
            if settings.switcherStyle == .titles {
                titlesRowView
            } else {
                cardBodyView
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            window.isHovered = hovering
            onHover(hovering)
        }
    }

    private var titlesRowView: some View {
        HStack(spacing: 10) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(window.windowTitle.isEmpty ? window.appName : window.windowTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.88))
                    .lineLimit(1)
                Text(window.appName)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            if window.isHovered || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(3.5)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 280, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? settings.accentColor.opacity(0.22) : (window.isHovered ? Color.white.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? settings.accentColor : Color.clear,
                    lineWidth: isSelected ? 2.0 : 0
                )
        )
    }

    private var cardBodyView: some View {
        let size = settings.cardSize

        return VStack(alignment: .leading, spacing: 6) {
            // 1. Header: App Icon (16x16) + Clean Title
            HStack(spacing: 6) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }

                Text(window.windowTitle.isEmpty ? window.appName : window.windowTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                if (window.isHovered || isSelected) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(3.5)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close window (W)")
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 5)

            // 2. Preview Area: Live uncropped screenshot OR Big Icon
            ZStack {
                if settings.switcherStyle == .thumbnails, let thumb = window.thumbnail {
                    // Screenshot preview
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: size.previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                } else if settings.switcherStyle == .thumbnails && window.isCapturing {
                    // Loading placeholder with App Icon while thumbnail renders
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.25))

                        if let icon = window.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: size.iconSize * 0.65, height: size.iconSize * 0.65)
                                .opacity(0.4)
                        }

                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    .frame(height: size.previewHeight)
                } else {
                    // Big App Icon (Comet, Figma, PDFgear, or App Icons mode)
                    VStack(spacing: 4) {
                        if let icon = window.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: size.iconSize, height: size.iconSize)
                                .clipShape(RoundedRectangle(cornerRadius: size.iconSize * 0.22, style: .continuous))
                                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                        } else {
                            Image(systemName: "macwindow")
                                .font(.system(size: size.iconSize * 0.6))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // Subtle active indicator dash underneath (as in reference screenshot)
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 14, height: 2.5)
                            .padding(.top, 2)
                    }
                    .frame(height: size.previewHeight)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .frame(width: computedCardWidth, height: size.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? settings.accentColor.opacity(0.20) : (window.isHovered ? Color.white.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? settings.accentColor : Color.clear,
                    lineWidth: isSelected ? 2.5 : 0
                )
        )
        .shadow(color: isSelected ? settings.accentColor.opacity(0.40) : Color.clear, radius: 8, x: 0, y: 3)
    }
}
