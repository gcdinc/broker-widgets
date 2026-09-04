import SwiftUI
import WidgetKit

struct PositionsWidgetView: View {
    var entry: PositionsEntry
    @Environment(\.widgetFamily) private var family

    private var rowLimit: Int {
        family == .systemLarge ? 8 : 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.snapshot.status == .ok, !entry.snapshot.positions.isEmpty {
                positionsList
            } else {
                statusMessage
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(URL(string: "brokerwidgets://open"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.broker.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if entry.snapshot.status == .ok {
                    Text(MoneyFormat.usd(entry.snapshot.totalValue))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            Spacer()
            if entry.snapshot.status == .ok {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(MoneyFormat.signedUsd(entry.snapshot.dayChangeValue))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(changeColor(entry.snapshot.dayChangeValue))
                    Text(MoneyFormat.percent(entry.snapshot.dayChangePercent))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(changeColor(entry.snapshot.dayChangeValue))
                }
            }
        }
    }

    private var positionsList: some View {
        let rows = Array(entry.snapshot.positions.prefix(rowLimit))
        let remaining = entry.snapshot.positions.count - rows.count
        return VStack(spacing: 4) {
            ForEach(rows) { position in
                HStack {
                    Text(position.symbol)
                        .font(.caption.monospaced().weight(.semibold))
                        .frame(width: 58, alignment: .leading)
                    Text(MoneyFormat.quantity(position.quantity))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(MoneyFormat.usd(position.resolvedMarketValue))
                        .font(.caption.monospacedDigit())
                    Text(MoneyFormat.signedUsd(position.dayChangeValue))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(changeColor(position.dayChangeValue))
                        .frame(width: 64, alignment: .trailing)
                }
            }
            if remaining > 0 {
                Text("+\(remaining) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusMessage: some View {
        Text(entry.snapshot.message ?? "Open Broker Widgets to finish setup.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func changeColor(_ value: Double) -> Color {
    if value > 0 { return .green }
    if value < 0 { return .red }
    return .secondary
}

#Preview("Fidelity medium", as: .systemMedium) {
    FidelityPositionsWidget()
} timeline: {
    PositionsEntry(date: .now, snapshot: .placeholder(.fidelity))
}
