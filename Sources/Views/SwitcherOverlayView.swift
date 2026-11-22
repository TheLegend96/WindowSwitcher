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
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .fullScreenUI
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = true
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

    // Split key windows into balanced rows (1 row if <= 5, 2 rows if > 5)
    private var rowsOfWindows: [[(index: Int, window: SwitcherWindow)]] {
        let indexed = Array(activeWindows.enumerated()).map { ($0.offset, $0.element) }
        guard !indexed.isEmpty else { return [] }
        if indexed.count <= 5 {
            return [indexed]
        }
        let mid = (indexed.count + 1) / 2
        let row1 = Array(indexed[0..<mid])
        let row2 = Array(indexed[mid..<indexed.count])
        return [row1, row2]
    }

    public var body: some View {
        hudContent
            .padding(28)
    }

    private var hudContent: some View {
        VStack(spacing: 12) {
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
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
                .padding(.horizontal, 4)
            }

            // MARK: - 2. Windows Grid / List (Full Mouse Hover & Click Support)
            if activeWindows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No windows matching \"\(state.searchText)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 440, height: 130)
            } else if settings.switcherStyle == .titles {
                // Vertical compact list layout
                VStack(spacing: 6) {
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
            } else {
                // 1 or 2 rows of dynamic-width cards (Thumbnails or App Icons)
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
        .padding(18)
        .background(
            ZStack {
                let r = CGFloat(settings.hudCornerRadius)

                // Layer 1: True optical see-through liquid glass base (clear vibrancy)
                ClearLiquidGlassBase(cornerRadius: r)

                // Layer 2: Clean, transparent optical glass tint
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Color(white: 0.10).opacity(0.24))

                // Layer 3: 10 o'clock Directional Specular Sheen (Shiny & Reflective)
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.40), location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.22),
                                .init(color: Color.clear, location: 0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Layer 4: Upper-crest Specular Glare (Wet Glass Luster)
                VStack {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 28)
                        .mask(
                            RoundedRectangle(cornerRadius: r, style: .continuous)
                        )
                    Spacer()
                }

                // Layer 5: Prismatic Chromatic Dispersion Edge (Refraction caustics)
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.95),                                 // 10 o'clock brilliant white
                                Color(red: 0.45, green: 0.85, blue: 1.0, opacity: 0.65), // Cyan dispersion
                                Color.white.opacity(0.35),
                                Color(red: 0.95, green: 0.45, blue: 0.85, opacity: 0.40), // Magenta dispersion
                                Color.black.opacity(0.45),                                 // 4 o'clock refraction shadow
                                Color(red: 0.5, green: 0.75, blue: 1.0, opacity: 0.35),   // Soft cyan rim
                                Color.white.opacity(0.95)                                  // Back to top-left
                            ]),
                            center: .center
                        ),
                        lineWidth: CGFloat(settings.borderWidth)
                    )

                // Layer 6: Inner Optical Bevel (Double-bevel physical glass thickness)
                RoundedRectangle(cornerRadius: max(0, r - 2), style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                    .padding(1.5)
            }
            // Dual Apple HIG elevation drop shadows (contact + ambient depth):
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
        )
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
