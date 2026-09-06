import SwiftUI
import AppKit

struct StatusView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            BrokerStatusCard(snapshot: appState.fidelitySnapshot)
            BrokerStatusCard(snapshot: appState.publicSnapshot)
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            HStack {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Label(appState.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)

                Button("Settings") {
                    openWindow(id: "main")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .task {
            appState.start()
            if appState.showPublicPanel {
                openWindow(id: "public-desktop")
            }
            if appState.showFidelityPanel {
                openWindow(id: "fidelity-desktop")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("AppMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("Broker Widgets")
                .font(.headline)
            Spacer()
            Text(RefreshSettings.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BrokerStatusCard: View {
    let snapshot: PortfolioSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.broker.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(snapshot.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if snapshot.status == .ok {
                HStack(alignment: .firstTextBaseline) {
                    Text(MoneyFormat.usd(snapshot.totalValue))
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Spacer()
                    Text("\(MoneyFormat.signedUsd(snapshot.dayChangeValue))  \(MoneyFormat.percent(snapshot.dayChangePercent))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(pnlColor(snapshot.dayChangeValue))
                }
                Text("\(snapshot.positions.count) positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(snapshot.message ?? snapshot.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

