import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

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
                snapshotSummary(appState.publicSnapshot)
            }

            Section("Fidelity") {
                Text("Fidelity has no official retail API. Sign in on their site in the in-app browser. Cookies stay in Keychain; this app never stores your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Sign in to Fidelity…") {
                        FidelityEngine.shared.openPositionsPage()
                        openWindow(id: "fidelity-login")
                    }
                    if appState.fidelitySignedIn {
                        Button("Sign out", role: .destructive) {
                            Task { await appState.signOutFidelity() }
                        }
                    }
                }
                snapshotSummary(appState.fidelitySnapshot)
            }

            Section("Status") {
                if let error = appState.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Last refresh completed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text("Drag a panel corner to resize. Panels sit with normal windows, not on top of other apps. Close with the × in the panel.")
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
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Label(appState.isRefreshing ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)
                Text("Default is hourly. Two floating desktop panels open automatically and update with the app. macOS WidgetKit widgets can still be added; keep this menu-bar app running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show floating desktop panels", isOn: $appState.showDesktopPanels)
                    .onChange(of: appState.showDesktopPanels) { _, show in
                        appState.setShowDesktopPanels(show)
                        if show {
                            openWindow(id: "public-desktop")
                            openWindow(id: "fidelity-desktop")
                        } else {
                            dismissWindow(id: "public-desktop")
                            dismissWindow(id: "fidelity-desktop")
                        }
                    }
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

    @ViewBuilder
    private func snapshotSummary(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.status == .ok {
                Text("\(MoneyFormat.usd(snapshot.totalValue))  \(MoneyFormat.signedUsd(snapshot.dayChangeValue))")
                    .font(.body.monospacedDigit())
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
