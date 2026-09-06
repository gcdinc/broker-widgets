import AppKit
import Foundation

enum AppUpdateInstall {
    static func install(
        remote: AppSoftwareVersion,
        latestLabel: String,
        progress: ((AppUpdateStatus) -> Void)?
    ) async throws -> AppUpdateStatus {
        guard let destination = installDestination else {
            throw AppUpdateError.copyToApplications
        }
        let downloaded = try await AppUpdateDownload.zip(from: remote.zipURL)
        defer { try? FileManager.default.removeItem(at: downloaded.directory) }
        let inspected = try AppUpdateDownload.version(fromAppAt: downloaded.appURL, zipURL: remote.zipURL)
        guard AppSoftwareVersion.isNewer(inspected, than: .local) else {
            return .upToDate
        }
        progress?(.installing)
        if destination.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            try stageRelaunch(from: downloaded.appURL, to: destination)
            return .installing
        }
        try replace(destination, with: downloaded.appURL)
        return .installed(latest: latestLabel)
    }

    private static var installDestination: URL? {
        let applications = URL(fileURLWithPath: "/Applications/BrokerWidgets.app")
        if FileManager.default.fileExists(atPath: applications.path) {
            return applications
        }
        let running = Bundle.main.bundleURL
        if running.path.contains("DerivedData") || running.path.contains("/Xcode/") {
            return nil
        }
        return running.pathExtension == "app" ? running : nil
    }

    private static func replace(_ destination: URL, with newApp: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try AppUpdateDownload.run("/usr/bin/ditto", arguments: [newApp.path, destination.path])
        try? AppUpdateDownload.run("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", destination.path])
    }

    private static func stageRelaunch(from newApp: URL, to destination: URL) throws {
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrokerWidgets-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        let staged = keep.appendingPathComponent("BrokerWidgets.app")
        try AppUpdateDownload.run("/usr/bin/ditto", arguments: [newApp.path, staged.path])
        let scriptURL = keep.appendingPathComponent("install.sh")
        try relaunchScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            destination.path,
            staged.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        try process.run()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private static let relaunchScript = """
    #!/bin/sh
    DEST="$1"
    SRC="$2"
    PID="$3"
    i=0
    while kill -0 "$PID" 2>/dev/null; do
      sleep 0.2
      i=$((i+1))
      [ "$i" -gt 50 ] && break
    done
    sleep 0.4
    rm -rf "$DEST"
    /usr/bin/ditto "$SRC" "$DEST"
    /usr/bin/xattr -dr com.apple.quarantine "$DEST" || true
    /usr/bin/open "$DEST"
    """
}
