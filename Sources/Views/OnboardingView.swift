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
            // MARK: - Branded Hero Header
            VStack(spacing: 12) {
                AppBrandingIcon(size: 64, cornerRadius: 15)
                    .padding(.top, 24)

                VStack(spacing: 4) {
                    Text("Welcome to Window Switcher")
                        .font(.system(size: 21, weight: .bold))

                    Text("Switch between individual windows on macOS with live 60 FPS previews and fluid keyboard control.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 18)

            Divider()

            // MARK: - Setup & Permissions Checklist
            VStack(spacing: 12) {
                HStack {
                    Text("Setup Permissions")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Required by macOS to switch & preview windows")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Step 1: Accessibility
                permissionStepCard(
                    stepNumber: 1,
                    title: "Accessibility Access",
                    description: "Enables keyboard shortcut detection (\(settings.primaryShortcut.rawValue)) and instantly brings your selected window to the front.",
                    icon: "keyboard.fill",
                    isGranted: permissions.hasAccessibility,
                    actionTitle: "Grant Permission",
                    action: { permissions.requestAccessibility() }
                )

                // Step 2: Screen Recording
                permissionStepCard(
                    stepNumber: 2,
                    title: "Screen Recording Access",
                    description: "Enables Apple ScreenCaptureKit on the GPU to stream live 60 FPS window previews. 100% private, stays on your device.",
                    icon: "macwindow.on.rectangle",
                    isGranted: permissions.hasScreenRecording,
                    actionTitle: "Grant Permission",
                    action: { permissions.requestScreenRecording() }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // MARK: - Interactive Quick Tip Card
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("How to Switch")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Hold **\(settings.primaryShortcut == .commandTab ? "⌘ Command" : "⌥ Option")** and tap **Tab** to cycle • Tap **W** to close any window • Release to switch.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            Divider()

            // MARK: - Clean Action Footer
            HStack(spacing: 12) {
                if allPermissionsGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("All permissions active")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Try Switcher") {
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
                        Text("Grant permissions above to start")
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
        .frame(width: 550, height: 490)
        .onAppear {
            permissions.checkPermissions()
        }
    }

    private func permissionStepCard(
        stepNumber: Int,
        title: String,
        description: String,
        icon: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Step / Granted indicator icon
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.12) : settings.accentColor.opacity(0.10))
                    .frame(width: 38, height: 38)

                if isGranted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(settings.accentColor)
                }
            }

            // Description text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Step \(stepNumber):")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action / Status Pill
            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Enabled")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isGranted ? Color.green.opacity(0.03) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isGranted ? Color.green.opacity(0.20) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
