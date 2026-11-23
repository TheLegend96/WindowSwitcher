import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var settings = SettingsManager.shared
    public var onComplete: () -> Void

    public init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    private var allPermissionsGranted: Bool {
        permissions.hasAccessibility && permissions.hasScreenRecording
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Hero with Cobalt Azure App Icon
            VStack(spacing: 12) {
                AppBrandingIcon(size: 64, cornerRadius: 15)
                    .padding(.top, 36)

                VStack(spacing: 5) {
                    Text("Welcome to Window Switcher")
                        .font(.system(size: 21, weight: .bold))

                    Text("Switch between individual windows on macOS with live 60 FPS previews and fluid keyboard control.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 20)

            Divider()

            // MARK: - Inset Grouped Permissions Checklist (Apple HIG System Settings Style)
            VStack(alignment: .leading, spacing: 8) {
                Text("Required Permissions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                VStack(spacing: 0) {
                    // Row 1: Accessibility
                    permissionRow(
                        icon: "keyboard",
                        title: "Accessibility",
                        subtitle: "Allows shortcut detection and window switching.",
                        isGranted: permissions.hasAccessibility,
                        action: { permissions.requestAccessibility() }
                    )

                    Divider()
                        .padding(.leading, 52)

                    // Row 2: Screen Recording
                    permissionRow(
                        icon: "macwindow.on.rectangle",
                        title: "Screen Recording",
                        subtitle: "Streams 60 FPS live previews. 100% private and on-device.",
                        isGranted: permissions.hasScreenRecording,
                        action: { permissions.requestScreenRecording() }
                    )
                }
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // MARK: - Interactive Product Experience & Keycap Preview
            MiniSwitcherPreview(
                shortcutName: settings.primaryShortcut.rawValue,
                accentColor: settings.accentColor
            )
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Spacer()

            Divider()

            // MARK: - Clean Action Footer
            HStack(spacing: 12) {
                if allPermissionsGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text("Ready to switch")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Test Switcher") {
                        SwitcherState.shared.show()
                    }
                    .controlSize(.regular)

                    Button("Get Started") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.65)
                        Text("Grant permissions above to begin")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Refresh Status") {
                        permissions.checkPermissions()
                    }
                    .controlSize(.regular)

                    Button("Skip for Now") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        onComplete()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 560)
        .onAppear {
            permissions.checkPermissions()
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isGranted ? Color.green.opacity(0.12) : settings.accentColor.opacity(0.10))
                    .frame(width: 32, height: 32)

                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 14, weight: isGranted ? .bold : .medium))
                    .foregroundColor(isGranted ? .green : settings.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Granted")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            } else {
                Button("Grant Access", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Mini Switcher Preview & Physical Keycaps
private struct MiniSwitcherPreview: View {
    let shortcutName: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 10) {
            // Live Glass Mockup
            HStack(spacing: 8) {
                miniCard(icon: "safari.fill", title: "Safari", isSelected: false)
                miniCard(icon: "curlybraces", title: "Xcode", isSelected: true)
                miniCard(icon: "terminal.fill", title: "Terminal", isSelected: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)

            // Physical Apple Keycaps
            HStack(spacing: 6) {
                KeycapView(key: shortcutName.contains("Option") ? "⌥ Option" : "⌘ Command")
                Text("+")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                KeycapView(key: "⇥ Tab")
                Text("to cycle •")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                KeycapView(key: "W")
                Text("to close • Release to switch")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func miniCard(icon: String, title: String, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(white: 0.20))
                    .frame(width: 68, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.7))
            }

            Text(title)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.20) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}

private struct KeycapView: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
    }
}
