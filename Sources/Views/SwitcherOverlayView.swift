import SwiftUI
import AppKit

// MARK: - Native Apple Liquid Glass View (Clear, See-Through, High-Transmittance)
public struct ClearLiquidGlassBase: NSViewRepresentable {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 26) {
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

public struct SwitcherOverlayView: View {
    @ObservedObject var state: SwitcherState
    @ObservedObject var settings = SettingsManager.shared

    public init(state: SwitcherState) {
        self.state = state
    }

    private var activeWindows: [SwitcherWindow] {
        state.filteredWindows
    }

    // Native Command+Tab App Icons prefers a single horizontal strip (wrapping cleanly only when exceeding row capacity)
    private var maxItemsPerRow: Int {
        if settings.switcherStyle == .icons {
            let maxRowWidth: CGFloat = 1120
            let stepW = settings.cardSize.iconSlotWidth + 10
            return max(5, min(10, Int(maxRowWidth / stepW)))
        }
        return 5
    }

    private var rowsOfWindows: [[(index: Int, window: SwitcherWindow)]] {
        let indexed = Array(activeWindows.enumerated()).map { ($0.offset, $0.element) }
        guard !indexed.isEmpty else { return [] }
        let limit = maxItemsPerRow
        if indexed.count <= limit {
            return [indexed]
        }
        let mid = (indexed.count + 1) / 2
        let row1 = Array(indexed[0..<mid])
        let row2 = Array(indexed[mid..<indexed.count])
        return [row1, row2]
    }

    private var effectiveCornerRadius: CGFloat {
        switch settings.switcherStyle {
        case .icons:
            // Deep macOS Command-Tab capsule curvature
            return rowsOfWindows.count <= 1 ? max(CGFloat(settings.hudCornerRadius), 38) : max(CGFloat(settings.hudCornerRadius), 28)
        case .titles:
            // Compact macOS list container curvature
            return min(CGFloat(settings.hudCornerRadius), 18)
        case .thumbnails:
            return CGFloat(settings.hudCornerRadius)
        }
    }

    public var body: some View {
        hudContent
            .padding(.horizontal, 90)
            .padding(.top, 70)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hudContent: some View {
        VStack(spacing: settings.switcherStyle == .titles ? 6 : 12) {
            // MARK: - 1. Real-Time Search Bar (Visible only when typing)
            if !state.searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.accentColor)

                    Text(state.searchText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("(\(activeWindows.count) of \(state.windows.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    Button(action: { state.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
                .padding(.horizontal, 4)
            }

            // MARK: - 2. Windows Grid / Strip / Vertical List
            if activeWindows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No windows matching \"\(state.searchText)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 420, height: 120)
            } else if settings.switcherStyle == .titles {
                // Reference-accurate 4-column Vertical List (App | Icon | Title | Status)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(activeWindows.enumerated()), id: \.element.id) { index, window in
                            WindowCardView(
                                window: window,
                                isSelected: index == state.selectedIndex,
                                onClose: {
                                    state.closeWindow(at: index)
                                },
                                onSelect: {
                                    state.commitSelection(for: window)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(activeWindows.count) * 34, 480))
            } else if settings.switcherStyle == .icons {
                // Native macOS Command-Tab Horizontal Capsule Strip with App Names Below
                VStack(spacing: 12) {
                    ForEach(0..<rowsOfWindows.count, id: \.self) { rowIdx in
                        HStack(spacing: 10) {
                            ForEach(rowsOfWindows[rowIdx], id: \.window.id) { item in
                                WindowCardView(
                                    window: item.window,
                                    isSelected: item.index == state.selectedIndex,
                                    onClose: {
                                        state.closeWindow(at: item.index)
                                    },
                                    onSelect: {
                                        state.commitSelection(for: item.window)
                                    }
                                )
                            }
                        }
                    }
                }
            } else {
                // Live Thumbnail Grid (1 or 2 rows)
                VStack(spacing: 12) {
                    ForEach(0..<rowsOfWindows.count, id: \.self) { rowIdx in
                        HStack(spacing: 12) {
                            ForEach(rowsOfWindows[rowIdx], id: \.window.id) { item in
                                WindowCardView(
                                    window: item.window,
                                    isSelected: item.index == state.selectedIndex,
                                    onClose: {
                                        state.closeWindow(at: item.index)
                                    },
                                    onSelect: {
                                        state.commitSelection(for: item.window)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, settings.switcherStyle == .titles ? 8 : (settings.switcherStyle == .icons ? 22 : 18))
        .padding(.vertical, settings.switcherStyle == .titles ? 8 : (settings.switcherStyle == .icons ? 16 : 18))
        .background(liquidGlassBackground)
    }

    // MARK: - Authentic Apple Liquid Glass Background (HIG Compliant)
    private var liquidGlassBackground: some View {
        let r = effectiveCornerRadius
        let isLightHUD = settings.themeMode == .light

        return ZStack {
            // 1. Floating depth shadows
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(isLightHUD ? Color.white.opacity(0.65) : Color(white: 0.10).opacity(0.62))
                .shadow(
                    color: Color.black.opacity(0.14),
                    radius: 2,
                    x: 0,
                    y: 1
                )
                .shadow(
                    color: Color.black.opacity(ambientShadowOpacity),
                    radius: ambientShadowRadius,
                    x: 0,
                    y: ambientShadowY
                )
                .shadow(
                    color: Color.black.opacity(directionalShadowOpacity),
                    radius: directionalShadowRadius,
                    x: 0,
                    y: directionalShadowY
                )

            // 2. Native macOS Liquid Glass Optical Material (Behind-Window Vibrancy)
            ClearLiquidGlassBase(cornerRadius: r)
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))

            // 3. Neutral smoky optical glass tint matching native Cmd-Tab depth & high legibility
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(isLightHUD ? Color.white.opacity(0.28) : Color(white: 0.06).opacity(0.46))

            // 4. Soft downward luminance sheen
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isLightHUD ? 0.30 : 0.14),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            // 5. Specular hairline catch around Liquid Glass rim
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.42), location: 0.0),
                            .init(color: Color.white.opacity(0.16), location: 0.45),
                            .init(color: Color.white.opacity(0.08), location: 0.80),
                            .init(color: Color.white.opacity(0.14), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(0.8, CGFloat(settings.borderWidth))
                )
        }
    }

    private var ambientShadowOpacity: Double {
        switch settings.shadowDepth {
        case "Subtle Depth": return 0.12
        case "Floating Deep": return 0.22
        default: return 0.16
        }
    }

    private var ambientShadowRadius: CGFloat {
        switch settings.shadowDepth {
        case "Subtle Depth": return 8
        case "Floating Deep": return 16
        default: return 12
        }
    }

    private var ambientShadowY: CGFloat {
        switch settings.shadowDepth {
        case "Subtle Depth": return 3
        case "Floating Deep": return 6
        default: return 4
        }
    }

    private var directionalShadowOpacity: Double {
        switch settings.shadowDepth {
        case "Subtle Depth": return 0.18
        case "Floating Deep": return 0.34
        default: return 0.24
        }
    }

    private var directionalShadowRadius: CGFloat {
        switch settings.shadowDepth {
        case "Subtle Depth": return 18
        case "Floating Deep": return 42
        default: return 30
        }
    }

    private var directionalShadowY: CGFloat {
        switch settings.shadowDepth {
        case "Subtle Depth": return 8
        case "Floating Deep": return 20
        default: return 14
        }
    }
}
