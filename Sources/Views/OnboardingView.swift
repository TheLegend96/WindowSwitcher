import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var updater = UpdateManager.shared
    public var onComplete: () -> Void

    public init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    private var allPermissionsGranted: Bool {
        permissions.hasAccessibility && permissions.hasScreenRecording
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Hero with Cobalt Azure App Icon
            VStack(spacing: 10) {
                AppBrandingIcon(size: 68, cornerRadius: 16)
                    .padding(.top, 24)

                Text("Welcome to Window Switcher")
                    .font(.system(size: 22, weight: .bold))

                Text("Experience fluid, 60 FPS live-mirrored window switching on macOS.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            // Step-by-Step System Permissions
            VStack(spacing: 12) {
                Text("System Permissions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 1. Accessibility
                permissionStepCard(
                    stepNumber: "1",
                    title: "Accessibility",
                    description: "Enables keyboard shortcut interception (⌘+Tab) and brings your chosen window to the front.",
                    icon: "command",
                    isGranted: permissions.hasAccessibility,
                    actionTitle: "Open Accessibility Settings",
                    action: { permissions.requestAccessibility() }
                )

                // 2. Screen Recording
                permissionStepCard(
                    stepNumber: "2",
                    title: "Screen Recording",
                    description: "Allows ScreenCaptureKit to stream live 60 FPS previews and uncropped window cards. 100% local, never stored.",
                    icon: "video.fill",
                    isGranted: permissions.hasScreenRecording,
                    actionTitle: "Open Screen Recording Settings",
                    action: { permissions.requestScreenRecording() }
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Update Check Section (Requested in setup guide)
            updateSection
                .padding(.horizontal, 22)
                .padding(.top, 10)

            Spacer()

            Divider()

            // Bottom Footer
            HStack(spacing: 12) {
                if allPermissionsGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Ready to Switch!")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }

                    Spacer()

                    Button("Test Switcher") {
                        SwitcherState.shared.show()
                    }

                    Button("Get Started") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.65)
                        Text("Waiting for permissions...")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Refresh Status") {
                        permissions.checkPermissions()
                    }

                    Button("Skip for Now") {
                        onComplete()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 530)
        .onAppear {
            permissions.checkPermissions()
        }
    }

    private var updateSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(settings.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Software Update")
                        .font(.system(size: 12, weight: .semibold))

                    Text("v\(updater.currentVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                switch updater.status {
                case .idle:
                    Text("Check for newer releases published on GitHub.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                case .checking:
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("Checking GitHub for updates...")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                case .upToDate:
                    Text("You have the latest version.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.green)
                case .available(let version, _, _, _):
                    Text("Version \(version) is available to install!")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(settings.accentColor)
                case .downloading(let progress):
                    Text("Downloading update: \(Int(progress * 100))%")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                case .installing:
                    Text("Installing update...")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                case .readyToRelaunch:
                    Text("Update ready to finish!")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.green)
                case .error(let message):
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            switch updater.status {
            case .idle, .upToDate, .error:
                Button("Check for Latest Update") {
                    updater.checkForUpdates(userInitiated: true)
                }
                .controlSize(.small)

            case .checking:
                ProgressView()
                    .scaleEffect(0.6)

            case .available(_, _, let downloadUrl, _):
                Button("Download & Install") {
                    updater.downloadAndInstall(from: downloadUrl)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 80)

            case .installing:
                ProgressView()
                    .scaleEffect(0.6)

            case .readyToRelaunch:
                Button("Relaunch") {
                    updater.relaunch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func permissionStepCard(
        stepNumber: String,
        title: String,
        description: String,
        icon: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : settings.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isGranted ? .green : settings.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if isGranted {
                        Text("Active")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Button(action: action) {
                            Text(actionTitle)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isGranted ? Color.green.opacity(0.04) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isGranted ? Color.green.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
