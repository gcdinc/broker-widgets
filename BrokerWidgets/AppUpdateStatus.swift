import Foundation

enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(latest: String)
    case downloading
    case installing
    case installed(latest: String)
    case failed(String)

    var message: String {
        switch self {
        case .idle: return "Not checked yet."
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're on the latest version."
        case .available(let latest): return "Version \(latest) is available."
        case .downloading: return "Downloading update…"
        case .installing: return "Installing update…"
        case .installed(let latest): return "Installed \(latest) in Applications."
        case .failed(let message): return message
        }
    }
}

enum AppUpdateSettings {
    static let autoKey = "autoUpdateEnabled"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }
}

enum AppUpdateError: LocalizedError {
    case invalidArchive
    case installFailed
    case copyToApplications

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The download from gcdsoftware.com was not a Broker Widgets app."
        case .installFailed:
            return "Could not replace the app. Try copying BrokerWidgets.zip from gcdsoftware.com/downloads/latest into /Applications."
        case .copyToApplications:
            return "Copy Broker Widgets to /Applications to enable updates."
        }
    }
}
