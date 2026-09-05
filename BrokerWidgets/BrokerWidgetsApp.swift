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
        .handlesExternalEvents(matching: Set<String>())

        Window("Fidelity Sign In", id: "fidelity-login") {
            FidelityLoginScreen()
                .environmentObject(appState)
        }
        .defaultSize(width: 860, height: 720)
        .handlesExternalEvents(matching: Set<String>())

        Window("Fidelity Positions", id: "fidelity-desktop") {
            DesktopPanelWindow(snapshot: appState.fidelitySnapshot, windowID: "fidelity-desktop")
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 360, height: 460)
        .defaultPosition(.topLeading)
        .handlesExternalEvents(matching: Set<String>())

        Window("Public Positions", id: "public-desktop") {
            DesktopPanelWindow(snapshot: appState.publicSnapshot, windowID: "public-desktop")
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 360, height: 460)
        .defaultPosition(.topTrailing)
        .handlesExternalEvents(matching: Set<String>())

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .handlesExternalEvents(matching: Set<String>())
    }
}
