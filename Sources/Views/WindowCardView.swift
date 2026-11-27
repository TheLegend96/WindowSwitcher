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

    // Dynamic width preserving true window proportions for thumbnails
    private var computedCardWidth: CGFloat {
        let size = settings.cardSize
        if settings.switcherStyle == .icons {
            return size.iconSlotWidth
        }
        if settings.switcherStyle == .titles {
            return 500
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
            let ratio = window.bounds.width / window.bounds.height
            let maxH: CGFloat = size.previewHeight
            let maxW: CGFloat = size.cardHeight * 1.55
            let calculatedW = min(max(maxH * ratio, 100), maxW)
            return max(calculatedW + 16, 140)
        }
        return size.iconSize + 36
    }

    public var body: some View {
        Button(action: onSelect) {
            switch settings.switcherStyle {
            case .titles:
                titlesRowView
            case .icons:
                commandTabIconView
            case .cards:
                compactCardView
            case .thumbnails:
                cardBodyView
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            window.isHovered = hovering
            onHover(hovering)
        }
    }

    private var isLightHUD: Bool {
        settings.themeMode == .light
    }

    // MARK: - 1. Native macOS Command-Tab App Icons View (Large Icon + Name Below)
    private var commandTabIconView: some View {
        let size = settings.cardSize
        let iconDim = size.iconSize
        let haloDim = iconDim + 12
        let haloRadius = haloDim * 0.26
        let labelFontSize: CGFloat = size == .small ? 11.5 : (size == .large ? 13.0 : 12.0)
        let subFontSize: CGFloat = size == .small ? 9.5 : (size == .large ? 11.0 : 10.5)
        let hasWindowSubtitle = !window.windowTitle.isEmpty && window.windowTitle != window.appName
        let titleInk: Color = isLightHUD
            ? (isSelected ? .black : Color.black.opacity(0.76))
            : (isSelected ? .white : Color.white.opacity(0.78))
        let subInk: Color = isLightHUD
            ? (isSelected ? Color.black.opacity(0.72) : Color.black.opacity(0.50))
            : (isSelected ? Color.white.opacity(0.80) : Color.white.opacity(0.52))

        return VStack(spacing: 6) {
            iconHaloStack(iconDim: iconDim, haloDim: haloDim, haloRadius: haloRadius)

            // App Name + Secondary Status/Title cleanly centered underneath
            VStack(spacing: 1.5) {
                Text(window.appName)
                    .font(.system(size: labelFontSize, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(titleInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if hasWindowSubtitle || window.isHidden || window.isMinimized {
                    HStack(spacing: 3) {
                        if window.isHidden || window.isMinimized {
                            Image(systemName: "eye.slash")
                                .font(.system(size: max(8.5, subFontSize - 1), weight: .medium))
                                .foregroundColor(subInk)
                        }

                        if hasWindowSubtitle {
                            Text(window.windowTitle)
                                .font(.system(size: subFontSize, weight: .regular))
                                .foregroundColor(subInk)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(height: 13)
                } else {
                    Spacer().frame(height: 13)
                }
            }
            .frame(width: size.iconSlotWidth - 4)
        }
        .frame(width: size.iconSlotWidth, height: size.iconSlotHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconHaloStack(iconDim: CGFloat, haloDim: CGFloat, haloRadius: CGFloat) -> some View {
        let baseFill: Color = isSelected
            ? settings.accentColor.opacity(isLightHUD ? 0.18 : 0.28)
            : (window.isHovered ? (isLightHUD ? Color.black.opacity(0.06) : Color.white.opacity(0.09)) : Color.clear)
        let highlightSheen: Color = isSelected ? Color.white.opacity(isLightHUD ? 0.25 : 0.14) : Color.clear
        let rimColor: Color = isSelected
            ? (isLightHUD ? settings.accentColor.opacity(0.60) : Color.white.opacity(0.40))
            : (window.isHovered ? Color.white.opacity(0.18) : Color.clear)
        let rimWidth: CGFloat = isSelected ? 1.0 : 0.75
        let haloShadow: Color = isSelected ? settings.accentColor.opacity(0.28) : Color.clear

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: haloRadius, style: .continuous)
                .fill(baseFill)
                .overlay(
                    RoundedRectangle(cornerRadius: haloRadius, style: .continuous)
                        .fill(highlightSheen)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: haloRadius, style: .continuous)
                        .stroke(rimColor, lineWidth: rimWidth)
                )
                .frame(width: haloDim, height: haloDim)
                .shadow(color: haloShadow, radius: 8, y: 2)

            Group {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconDim, height: iconDim)
                        .shadow(color: Color.black.opacity(0.28), radius: 5, x: 0, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: iconDim * 0.22, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: iconDim, height: iconDim)
                        .overlay(
                            Image(systemName: "macwindow")
                                .font(.system(size: iconDim * 0.45))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
            }
            .frame(width: haloDim, height: haloDim)

            if window.isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(width: 16, height: 16)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .help("Close window (W)")
            }
        }
    }

    // MARK: - 2. Vertical 4-Column Window Titles List View (App | Icon | Title | Status)
    private var titlesRowView: some View {
        let appInk: Color = isSelected ? .white : (isLightHUD ? Color.black.opacity(0.74) : Color.white.opacity(0.80))
        let titleInk: Color = isSelected ? .white : (isLightHUD ? Color.black.opacity(0.90) : Color.white.opacity(0.94))
        let statusInk: Color = isSelected ? Color.white.opacity(0.92) : (isLightHUD ? Color.black.opacity(0.45) : Color.white.opacity(0.48))
        let hoverFill: Color = isLightHUD ? Color.black.opacity(0.06) : Color.white.opacity(0.08)

        return HStack(spacing: 10) {
            // Column 1: Right-aligned App Name
            Text(window.appName)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundColor(appInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 84, alignment: .trailing)

            // Column 2: Compact App Icon
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 19, height: 19)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 14))
                    .foregroundColor(appInk)
                    .frame(width: 19, height: 19)
            }

            // Column 3: Left-aligned Window Title
            Text(window.windowTitle.isEmpty ? window.appName : window.windowTitle)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundColor(titleInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Column 4: Hidden/Minimized Status Badge & Hover Close Button
            HStack(spacing: 6) {
                if window.isHidden || window.isMinimized {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusInk)
                }

                if window.isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(isSelected ? 0.25 : 0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close window (W)")
                }
            }
            .frame(minWidth: 20, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(width: 500, height: 31)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? settings.accentColor : (window.isHovered ? hoverFill : Color.clear))
        )
        .contentShape(Rectangle())
    }

    // MARK: - 3. Bento Compact Card View (App Icon + Crisp Title + Subtitle)
    private var compactCardView: some View {
        let titleInk: Color = isLightHUD ? Color.black.opacity(0.92) : .white
        let subInk: Color = isLightHUD ? Color.black.opacity(0.58) : Color.white.opacity(0.68)
        let cardFill: Color = isSelected
            ? settings.accentColor.opacity(isLightHUD ? 0.16 : 0.28)
            : (window.isHovered ? (isLightHUD ? Color.black.opacity(0.05) : Color.white.opacity(0.09)) : (isLightHUD ? Color.white.opacity(0.50) : Color.white.opacity(0.05)))
        let borderInk: Color = isSelected
            ? settings.accentColor
            : (isLightHUD ? Color.black.opacity(0.10) : Color.white.opacity(0.10))

        return HStack(spacing: 12) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.black.opacity(0.24), radius: 4, y: 2)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 24))
                    .foregroundColor(subInk)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 2.5) {
                Text(window.windowTitle.isEmpty ? window.appName : window.windowTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(titleInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(window.appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(subInk)
                        .lineLimit(1)

                    if window.isHidden || window.isMinimized {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(subInk.opacity(0.85))
                    }
                }
            }

            Spacer(minLength: 2)

            if window.isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                        .frame(width: 17, height: 17)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close window (W)")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 226, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderInk, lineWidth: isSelected ? 1.6 : 0.75)
        )
        .shadow(color: isSelected ? settings.accentColor.opacity(0.26) : .clear, radius: 6, y: 2)
        .contentShape(Rectangle())
    }

    // MARK: - 4. Live Preview Thumbnail Card View
    private var cardBodyView: some View {
        let size = settings.cardSize

        return VStack(alignment: .leading, spacing: 6) {
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
                    .help("Close window (W)")
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 5)

            ZStack {
                if let thumb = window.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: size.previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                } else if window.isCapturing {
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
