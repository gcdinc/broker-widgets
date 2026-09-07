import Foundation

enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(latest: String)
    case failed(String)

    var message: String {
        switch self {
        case .idle: return "Not checked yet."
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're on the latest version."
        case .available(let latest): return "Version \(latest) is available."
        case .failed(let message): return message
        }
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

enum AppUpdateError: LocalizedError {
    case invalidArchive

    var errorDescription: String? {
        "The download from gcdsoftware.com was not a Broker Widgets app."
    }
}
