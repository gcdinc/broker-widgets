import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

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
                        try? appState.savePublicSecret()
                        Task { await appState.refreshPublic() }
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

            Section("Refresh") {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Label(appState.isRefreshing ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)
                Text("The menu-bar app must stay running so widgets can update. Add both widgets from the desktop / Notification Center gallery after the first launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Text(position.symbol).font(.caption.monospaced()).frame(width: 64, alignment: .leading)
                        Text(MoneyFormat.quantity(position.quantity)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(MoneyFormat.usd(position.resolvedMarketValue)).font(.caption.monospacedDigit())
                    }
                }
            } else if let message = snapshot.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
