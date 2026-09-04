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
        }
        .onOpenURL { _ in
            openWindow(id: "main")
        }
    }

    private var header: some View {
        HStack {
            Text("Broker Widgets")
                .font(.headline)
            Spacer()
            Text("every 5 min")
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
                        .foregroundStyle(changeColor(snapshot.dayChangeValue))
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

func changeColor(_ value: Double) -> Color {
    if value > 0 { return .green }
    if value < 0 { return .red }
    return .secondary
}
