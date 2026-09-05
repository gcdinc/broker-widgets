import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static let defaultsKey = "launchAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(enabled, forKey: defaultsKey)
        } catch {
            UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
        }
    }

    /// First launch turns login-item on so the menu bar app starts with the Mac.
    static func enableOnFirstLaunchIfNeeded() {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            setEnabled(true)
            return
        }
        if UserDefaults.standard.bool(forKey: defaultsKey), !isEnabled {
            setEnabled(true)
        }
    }
}
