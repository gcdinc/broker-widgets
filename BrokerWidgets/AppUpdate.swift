import Foundation

enum AppUpdate {
    private static let etagKey = "update.lastETag"
    private static let modifiedKey = "update.lastModified"
    private static let remoteVersionKey = "update.lastRemoteVersion"
    private static let remoteBuildKey = "update.lastRemoteBuild"

    static var currentVersionLabel: String {
        "\(AppSoftwareVersion.local.marketing) (\(AppSoftwareVersion.local.build))"
    }

    static func check(
        installIfAvailable: Bool,
        progress: ((AppUpdateStatus) -> Void)? = nil
    ) async throws -> AppUpdateStatus {
        progress?(.checking)
        let remote = try await fetchRemoteVersion()
        UserDefaults.standard.set(Date(), forKey: "update.lastCheckedAt")
        guard AppSoftwareVersion.isNewer(remote, than: .local) else {
            return .upToDate
        }
        let label = "\(remote.marketing) (\(remote.build))"
        guard installIfAvailable else {
            return .available(latest: label)
        }
        progress?(.downloading)
        return try await AppUpdateInstall.install(remote: remote, latestLabel: label, progress: progress)
    }

    private struct Manifest: Decodable {
        let version: String
        let build: String?
        let url: URL?
    }

    private struct ZipHead {
        let etag: String?
        let modified: String?
    }

    private static func fetchRemoteVersion() async throws -> AppSoftwareVersion {
        if let manifest = try? await fetchManifest() {
            cache(version: manifest.version, build: manifest.build ?? "0", etag: nil, modified: nil)
            return AppSoftwareVersion(
                marketing: manifest.version,
                build: manifest.build ?? "0",
                zipURL: manifest.url ?? AppConstants.latestZipURL
            )
        }
        let head = try await headZip()
        if let cached = cachedVersion(matching: head) {
            return cached
        }
        let downloaded = try await AppUpdateDownload.zip()
        defer { try? FileManager.default.removeItem(at: downloaded.directory) }
        let inspected = try AppUpdateDownload.version(fromAppAt: downloaded.appURL, zipURL: AppConstants.latestZipURL)
        cache(version: inspected.marketing, build: inspected.build, etag: head.etag, modified: head.modified)
        return inspected
    }

    private static func fetchManifest() async throws -> Manifest {
        var request = URLRequest(url: AppConstants.latestVersionURL)
        request.timeoutInterval = 8
        request.setValue(AppUpdateDownload.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private static func headZip() async throws -> ZipHead {
        var request = URLRequest(url: AppConstants.latestZipURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        request.setValue(AppUpdateDownload.userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return ZipHead(
            etag: http.value(forHTTPHeaderField: "ETag"),
            modified: http.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    private static func cachedVersion(matching head: ZipHead) -> AppSoftwareVersion? {
        let defaults = UserDefaults.standard
        let sameETag = head.etag != nil && head.etag == defaults.string(forKey: etagKey)
        let sameModified = head.modified != nil && head.modified == defaults.string(forKey: modifiedKey)
        guard sameETag || sameModified,
              let marketing = defaults.string(forKey: remoteVersionKey),
              let build = defaults.string(forKey: remoteBuildKey)
        else { return nil }
        return AppSoftwareVersion(marketing: marketing, build: build, zipURL: AppConstants.latestZipURL)
    }

    private static func cache(version: String, build: String, etag: String?, modified: String?) {
        let defaults = UserDefaults.standard
        defaults.set(version, forKey: remoteVersionKey)
        defaults.set(build, forKey: remoteBuildKey)
        if let etag { defaults.set(etag, forKey: etagKey) }
        if let modified { defaults.set(modified, forKey: modifiedKey) }
    }
}
