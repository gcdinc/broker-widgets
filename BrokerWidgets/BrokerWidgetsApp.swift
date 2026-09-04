import SwiftUI

@main
struct BrokerWidgetsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            StatusView()
                .environmentObject(appState)
        } label: {
            Label("Broker Widgets", systemImage: appState.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Broker Widgets", id: "main") {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 560, minHeight: 480)
        }
        .defaultSize(width: 640, height: 560)

        Window("Fidelity Sign In", id: "fidelity-login") {
            FidelityLoginScreen()
                .environmentObject(appState)
        }
        .defaultSize(width: 860, height: 720)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
