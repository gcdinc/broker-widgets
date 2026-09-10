import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var confirmClearSecrets = false

    var body: some View {
        Form {
            Section("Public.com") {
                if appState.hasPublicSecret {
                    Label("API secret stored in Keychain", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                    Button("Remove Public secret", role: .destructive) {
                        appState.clearPublicSecret()
                    }
                } else {
                    SecureField("Paste Individual API secret", text: $appState.publicSecretDraft)
                    Text("Generate this in Public → Settings. It is never written to disk or git.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Save secret to Keychain") {
                        Task { await appState.savePublicSecretAndRefresh() }
                    }
                    .disabled(appState.publicSecretDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Toggle("Show widget", isOn: $appState.showPublicPanel)
                    .onChange(of: appState.showPublicPanel) { _, show in
                        setPanel("public-desktop", show)
                    }
                snapshotSummary(appState.publicSnapshot)
            }

            Section("Fidelity") {
                Text("Fidelity has no official retail API. Sign in on their site in the in-app browser. Cookies stay in Keychain; this app never stores your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(appState.fidelitySignedIn ? "Open Fidelity session…" : "Sign in to Fidelity…") {
                        openWindow(id: "fidelity-login")
                    }
                    if appState.fidelitySignedIn {
                        Button("Sign out", role: .destructive) {
                            Task { await appState.signOutFidelity() }
                        }
                    }
                }
                Toggle("Show widget", isOn: $appState.showFidelityPanel)
                    .onChange(of: appState.showFidelityPanel) { _, show in
                        setPanel("fidelity-desktop", show)
                    }
                snapshotSummary(appState.fidelitySnapshot)
            }

            Section("Status") {
                lastUpdatedLabel
                if let error = appState.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Clear all secrets", role: .destructive) {
                    confirmClearSecrets = true
                }
                .foregroundStyle(.red)
                .confirmationDialog(
                    "Remove the Public API secret and Fidelity cookies from Keychain?",
                    isPresented: $confirmClearSecrets,
                    titleVisibility: .visible
                ) {
                    Button("Clear all secrets", role: .destructive) {
                        Task { await appState.clearAllSecrets() }
                    }
                }
            }

            Section("Display") {
                Picker("Panel font size", selection: $appState.panelFontScale) {
                    ForEach(DisplaySettings.fontChoices, id: \.scale) { choice in
                        Text(choice.label).tag(choice.scale)
                    }
                }
                .onChange(of: appState.panelFontScale) { _, scale in
                    appState.setPanelFontScale(scale)
                }
                Toggle("Always on top", isOn: $appState.panelsAlwaysOnTop)
                    .onChange(of: appState.panelsAlwaysOnTop) { _, enabled in
                        appState.setPanelsAlwaysOnTop(enabled)
                    }
                Text("Drag a panel corner to resize. Close with the × in the panel. Always on top keeps the panels above other windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Text("This copy is \(AppUpdate.currentVersionLabel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.updateStatus.message)
                    .font(.caption)
                    .foregroundStyle(updateStatusColor)
                Button {
                    Task { await appState.checkForAppUpdate() }
                } label: {
                    Label(appState.isUpdating ? "Checking…" : "Check for updates", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isUpdating)
                if appState.updateStatus.isAvailable {
                    Button {
                        NSWorkspace.shared.open(AppConstants.productPageURL)
                    } label: {
                        Label("Go to download page", systemImage: "safari")
                    }
                }
                Text("The app cannot replace itself. Download BrokerWidgets.zip from gcdsoftware.com and drop the new app on Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open Broker Widgets at login", isOn: $appState.launchAtLogin)
                    .onChange(of: appState.launchAtLogin) { _, enabled in
                        appState.setLaunchAtLogin(enabled)
                    }
                Text("Keeps the menu bar app and desktop panels running after you restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Refresh") {
                Picker("Update widgets", selection: $appState.refreshInterval) {
                    ForEach(RefreshSettings.choices, id: \.seconds) { choice in
                        Text(choice.label).tag(choice.seconds)
                    }
                }
                .onChange(of: appState.refreshInterval) { _, seconds in
                    appState.setRefreshInterval(seconds)
                }
                Button("Reset to default") {
                    appState.resetRefreshInterval()
                }
                .disabled(appState.refreshInterval == RefreshSettings.defaultSeconds)
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Label(appState.isRefreshing ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)
                Text("Default is hourly. Use Show widget under each broker to open or hide that desktop panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !SnapshotStore.isAvailable {
                    Text("App Group is unavailable, so widgets cannot read holdings. In Xcode enable App Groups (`group.com.gcd.BrokerWidgets`) on both targets.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            appState.start()
        }
    }

    private func setPanel(_ windowID: String, _ show: Bool) {
        appState.setPanelVisible(windowID, show)
        if show {
            openWindow(id: windowID)
        } else {
            DesktopPanelWindows.close(windowID)
        }
    }

    private var lastUpdatedLabel: some View {
        Text(lastUpdatedText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var lastUpdatedText: String {
        guard let date = appState.lastHoldingsUpdate else {
            return "Last updated: never"
        }
        return "Last updated \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var updateStatusColor: Color {
        switch appState.updateStatus {
        case .failed:
            return .red
        case .available:
            return .green
        default:
            return .secondary
        }
    }

    @ViewBuilder
    private func snapshotSummary(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.status == .ok {
                Text("\(MoneyFormat.usd(snapshot.totalValue))  \(MoneyFormat.signedUsd(snapshot.dayChangeValue))")
                    .font(.body.monospacedDigit())
                Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(snapshot.positions.prefix(8)) { position in
                    HStack {
                        Text(position.displaySymbol).font(.caption.monospaced()).frame(width: 88, alignment: .leading)
                        Text(position.displayAccountName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(MoneyFormat.usd(position.resolvedMarketValue)).font(.caption.monospacedDigit())
                        Text(MoneyFormat.percent(position.resolvedDayChangePercent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(pnlColor(position.resolvedDayChangePercent))
                    }
                }
            } else if snapshot.status == .error, let message = snapshot.message {
                Text(message).font(.caption).foregroundStyle(.red)
            } else if let message = snapshot.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
