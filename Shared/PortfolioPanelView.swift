import AppKit
import SwiftUI

private enum PositionSortColumn: String, CaseIterable {
    case symbol, quantity, value, change

    var title: String {
        switch self {
        case .symbol: return "Symbol"
        case .quantity: return "Qty"
        case .value: return "Value"
        case .change: return "Chg"
        }
    }
}

struct PortfolioPanelView: View {
    let snapshot: PortfolioSnapshot
    var scrollable: Bool = false
    var fontScale: Double = 1
    var maxRows: Int? = nil
    var showsClose: Bool = false
    var onClose: (() -> Void)?

    @State private var sortColumn: PositionSortColumn = .value
    @State private var sortAscending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * fontScale) {
            header
            if snapshot.status == .ok, !snapshot.positions.isEmpty {
                columnHeader
                let groups = accountGroups(from: snapshot.positions, limit: maxRows)
                if scrollable {
                    ScrollView {
                        positionsList(groups: groups)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    positionsList(groups: groups)
                }
            } else {
                Text(snapshot.message ?? "Open Broker Widgets to finish setup.")
                    .font(scaled(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.broker.displayName)
                    .font(scaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if snapshot.status == .ok {
                    Text(MoneyFormat.usd(snapshot.totalValue))
                        .font(scaled(20, weight: .semibold, mono: true))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if snapshot.status == .ok {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(MoneyFormat.signedUsd(snapshot.dayChangeValue))
                        .font(scaled(11, weight: .semibold, mono: true))
                        .foregroundStyle(pnlColor(snapshot.dayChangeValue))
                    Text(MoneyFormat.percent(snapshot.dayChangePercent))
                        .font(scaled(10, mono: true))
                        .foregroundStyle(pnlColor(snapshot.dayChangeValue))
                }
            }
            if showsClose {
                PanelCloseButton(action: { onClose?() })
                    .frame(width: 24, height: 24)
                    .help("Close")
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortButton(.symbol, width: 72 * fontScale, alignment: .leading)
            sortButton(.quantity, width: 44 * fontScale, alignment: .leading)
            Spacer(minLength: 8)
            sortButton(.value, width: 72 * fontScale, alignment: .trailing)
            sortButton(.change, width: 58 * fontScale, alignment: .trailing)
        }
        .padding(.bottom, 2)
    }

    private func sortButton(_ column: PositionSortColumn, width: CGFloat, alignment: Alignment) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = column == .symbol
            }
        } label: {
            HStack(spacing: 2) {
                Text(column.title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7 * fontScale, weight: .bold))
                }
            }
            .font(scaled(9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func positionsList(groups: [AccountPositionGroup]) -> some View {
        LazyVStack(alignment: .leading, spacing: 10 * fontScale) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4 * fontScale) {
                    HStack {
                        Text(group.name)
                            .font(scaled(10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if let move = snapshot.dayMove(forAccountId: group.id), move.dayChangePercent != 0 || move.dayChangeValue != 0 {
                            Text(MoneyFormat.percent(move.dayChangePercent))
                                .font(scaled(10, weight: .semibold, mono: true))
                                .foregroundStyle(pnlColor(move.dayChangePercent))
                        }
                    }
                    Divider()
                    ForEach(sorted(group.positions)) { position in
                        positionRow(position)
                    }
                }
            }
        }
    }

    private func positionRow(_ position: Position) -> some View {
        let move = position.resolvedDayChangePercent
        return HStack(spacing: 0) {
            Text(position.displaySymbol)
                .font(scaled(11, weight: .semibold, mono: true))
                .lineLimit(1)
                .frame(width: 72 * fontScale, alignment: .leading)
            Text(MoneyFormat.quantity(position.quantity))
                .font(scaled(10))
                .foregroundStyle(.secondary)
                .frame(width: 44 * fontScale, alignment: .leading)
            Spacer(minLength: 8)
            Text(MoneyFormat.usd(position.resolvedMarketValue))
                .font(scaled(11, mono: true))
                .frame(width: 72 * fontScale, alignment: .trailing)
            Text(MoneyFormat.percent(move))
                .font(scaled(10, mono: true))
                .foregroundStyle(pnlColor(move))
                .frame(width: 58 * fontScale, alignment: .trailing)
        }
    }

    private func sorted(_ positions: [Position]) -> [Position] {
        positions.sorted { lhs, rhs in
            let ascending = sortAscending
            let less: Bool
            switch sortColumn {
            case .symbol:
                less = lhs.displaySymbol.localizedCaseInsensitiveCompare(rhs.displaySymbol) == .orderedAscending
            case .quantity:
                less = lhs.quantity < rhs.quantity
            case .value:
                less = lhs.resolvedMarketValue < rhs.resolvedMarketValue
            case .change:
                less = lhs.resolvedDayChangePercent < rhs.resolvedDayChangePercent
            }
            return ascending ? less : !less
        }
    }

    private func accountGroups(from positions: [Position], limit: Int?) -> [AccountPositionGroup] {
        let grouped = Dictionary(grouping: positions) { $0.accountId ?? $0.displayAccountName }
        let ordered = grouped.values
            .map { rows -> AccountPositionGroup in
                AccountPositionGroup(
                    id: rows.first?.accountId ?? rows.first?.displayAccountName ?? "account",
                    name: rows.first?.displayAccountName ?? "Account",
                    positions: rows
                )
            }
            .sorted { lhs, rhs in
                lhs.positions.reduce(0) { $0 + $1.resolvedMarketValue }
                    > rhs.positions.reduce(0) { $0 + $1.resolvedMarketValue }
            }
        guard let limit else { return ordered }
        var remaining = limit
        var result: [AccountPositionGroup] = []
        for group in ordered {
            guard remaining > 0 else { break }
            let slice = Array(sorted(group.positions).prefix(remaining))
            remaining -= slice.count
            result.append(AccountPositionGroup(id: group.id, name: group.name, positions: slice))
        }
        return result
    }

    private func scaled(_ size: CGFloat, weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        .system(size: size * fontScale, weight: weight, design: mono ? .monospaced : .default)
    }
}

private struct AccountPositionGroup: Identifiable {
    var id: String
    var name: String
    var positions: [Position]
}

func pnlColor(_ value: Double) -> Color {
    if value > 0 { return .green }
    if value < 0 { return .red }
    return .secondary
}

/// Real NSButton so window-drag (`isMovableByWindowBackground`) does not swallow the click.
struct PanelCloseButton: NSViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.title = ""
        button.bezelStyle = .circular
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.tap)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
