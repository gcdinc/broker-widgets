import Foundation

enum RefreshSettings {
    static let key = "refreshIntervalSeconds"
    static let defaultSeconds: TimeInterval = 60 * 60

    static let choices: [(label: String, seconds: TimeInterval)] = [
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("4 hours", 4 * 60 * 60)
    ]

    static var seconds: TimeInterval {
        get {
            let stored = suite.double(forKey: key)
            return stored > 0 ? stored : defaultSeconds
        }
        set {
            suite.set(newValue, forKey: key)
        }
    }

    static var label: String {
        choices.first(where: { $0.seconds == seconds })?.label ?? "1 hour"
    }

    static var suite: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }
}
