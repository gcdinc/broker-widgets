import Foundation

enum AppUpdateDownload {
    static func zip(from url: URL = AppConstants.latestZipURL) async throws -> (directory: URL, appURL: URL) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrokerWidgets-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zipURL = work.appendingPathComponent("BrokerWidgets.zip")
        try FileManager.default.copyItem(at: tempURL, to: zipURL)
        let extract = work.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extract.path])
        let appURL = extract.appendingPathComponent("BrokerWidgets.app")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppUpdateError.invalidArchive
        }
        return (work, appURL)
    }

    static func version(fromAppAt appURL: URL, zipURL: URL) throws -> AppSoftwareVersion {
        let plist = try readPlist(appURL.appendingPathComponent("Contents/Info.plist"))
        guard plist["CFBundleIdentifier"] as? String == "com.gcd.BrokerWidgets" else {
            throw AppUpdateError.invalidArchive
        }
        return AppSoftwareVersion(
            marketing: plist["CFBundleShortVersionString"] as? String ?? "0",
            build: plist["CFBundleVersion"] as? String ?? "0",
            zipURL: zipURL
        )
    }

    private static func run(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.invalidArchive
        }
    }

    static var userAgent: String {
        "BrokerWidgets/\(AppSoftwareVersion.local.marketing)"
    }

    private static func readPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let plist = object as? [String: Any] else { throw AppUpdateError.invalidArchive }
        return plist
    }
}
