import Foundation

enum DisplaySettings {
    static let fontScaleKey = "panelFontScale"

    static let fontChoices: [(label: String, scale: Double)] = [
        ("Small", 0.85),
        ("Default", 1.0),
        ("Large", 1.2),
        ("Extra large", 1.4)
    ]

    static var fontScale: Double {
        get {
            let stored = suite.double(forKey: fontScaleKey)
            return stored > 0 ? stored : 1.0
        }
        set {
            suite.set(newValue, forKey: fontScaleKey)
        }
    }

    static var suite: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }
}
