import Foundation
import AppKit
import Combine

public enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case available(version: String, notes: String, downloadUrl: URL, htmlUrl: URL)
    case downloading(progress: Double)
    case installing
    case readyToRelaunch
    case error(message: String)
}

public struct GitHubRelease: Codable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct GitHubAsset: Codable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

@MainActor
public class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = UpdateManager()

    // Configurable repo slug, defaulting to project repo
    @Published public var repoOwner: String = "pruthvirajmane"
    @Published public var repoName: String = "mac-window-switcher"

    @Published public var status: UpdateStatus = .idle
    @Published public var downloadProgress: Double = 0.0
    @Published public var isChecking: Bool = false
    @Published public var showUpdateSheet: Bool = false
    @Published public var lastCheckDate: Date? = nil

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var activeDownloadUrl: URL?

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private override init() {
        super.init()
    }

    // MARK: - Check For Updates
    public func checkForUpdates(userInitiated: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        status = .checking

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            status = .error(message: "Invalid repository URL")
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("WindowSwitcher-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid network response."])
                }

                if httpResponse.statusCode == 404 {
                    // No releases published yet on repository
                    await MainActor.run {
                        self.isChecking = false
                        self.lastCheckDate = Date()
                        self.status = .upToDate(version: self.currentVersion)
                        if userInitiated {
                            self.showUpdateSheet = true
                        }
                    }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    let msg = "GitHub API returned status \(httpResponse.statusCode)"
                    await MainActor.run {
                        self.isChecking = false
                        self.status = .error(message: msg)
                        if userInitiated { self.showUpdateSheet = true }
                    }
                    return
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let hasNewer = self.isVersion(latestTag, newerThan: self.currentVersion)

                await MainActor.run {
                    self.isChecking = false
                    self.lastCheckDate = Date()

                    if hasNewer {
                        // Find .dmg asset
                        let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
                        let downloadUrl = dmgAsset.flatMap { URL(string: $0.browserDownloadUrl) } ?? URL(string: release.htmlUrl)!
                        let htmlUrl = URL(string: release.htmlUrl) ?? downloadUrl

                        self.status = .available(
                            version: latestTag,
                            notes: release.body ?? release.name ?? "Bug fixes and performance improvements.",
                            downloadUrl: downloadUrl,
                            htmlUrl: htmlUrl
                        )
                        self.showUpdateSheet = true
                    } else {
                        self.status = .upToDate(version: self.currentVersion)
                        if userInitiated {
                            self.showUpdateSheet = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                    self.status = .error(message: error.localizedDescription)
                    if userInitiated { self.showUpdateSheet = true }
                }
            }
        }
    }

    // MARK: - Semantic Version Comparison
    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }

    // MARK: - Download and 1-Click Install Update
    public func downloadAndInstall(from url: URL) {
        guard case .available = status else { return }
        status = .downloading(progress: 0.0)
        downloadProgress = 0.0

        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }

    // URLSessionDownloadDelegate methods
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        Task { @MainActor in
            self.downloadProgress = progress
            self.status = .downloading(progress: progress)
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy downloaded file to temp directory
        let tempDmg = FileManager.default.temporaryDirectory.appendingPathComponent("WindowSwitcher-Update.dmg")
        try? FileManager.default.removeItem(at: tempDmg)

        do {
            try FileManager.default.copyItem(at: location, to: tempDmg)
            Task { @MainActor in
                self.performInstallation(from: tempDmg)
            }
        } catch {
            Task { @MainActor in
                self.status = .error(message: "Failed to save downloaded update: \(error.localizedDescription)")
            }
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Task { @MainActor in
                self.status = .error(message: "Download failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Mount DMG and Replace /Applications/WindowSwitcher.app
    private func performInstallation(from dmgUrl: URL) {
        self.status = .installing

        DispatchQueue.global(qos: .userInitiated).async {
            let dmgPath = dmgUrl.path
            let mountProcess = Process()
            mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mountProcess.arguments = ["attach", dmgPath, "-nobrowse", "-noverify", "-plist"]

            let pipe = Pipe()
            mountProcess.standardOutput = pipe
            do {
                try mountProcess.run()
                mountProcess.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let entities = plist["system-entities"] as? [[String: Any]] else {
                    throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to mount update disk image."])
                }

                var mountPoint: String? = nil
                for entity in entities {
                    if let mp = entity["mount-point"] as? String {
                        mountPoint = mp
                        break
                    }
                }

                guard let volume = mountPoint else {
                    throw NSError(domain: "UpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Volume mount point not found."])
                }

                let sourceApp = "\(volume)/WindowSwitcher.app"
                let targetApp = "/Applications/WindowSwitcher.app"

                guard FileManager.default.fileExists(atPath: sourceApp) else {
                    throw NSError(domain: "UpdateManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "WindowSwitcher.app not found in disk image."])
                }

                // Replace /Applications/WindowSwitcher.app using script
                let replaceScript = """
                rm -rf "\(targetApp)"
                cp -R "\(sourceApp)" "\(targetApp)"
                hdiutil detach "\(volume)" -force || true
                """

                let scriptProcess = Process()
                scriptProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
                scriptProcess.arguments = ["-c", replaceScript]
                try scriptProcess.run()
                scriptProcess.waitUntilExit()

                DispatchQueue.main.async {
                    self.status = .readyToRelaunch
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .error(message: "Installation error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Relaunch App
    public func relaunch() {
        let appPath = "/Applications/WindowSwitcher.app"
        let script = "sleep 0.5; open \"\(appPath)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }
}
