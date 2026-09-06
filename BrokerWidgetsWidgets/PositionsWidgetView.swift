import SwiftUI
import WidgetKit

struct PositionsWidgetView: View {
    var entry: PositionsEntry
    @Environment(\.widgetFamily) private var family

    private var rowLimit: Int {
        family == .systemLarge ? 8 : 4
    }

    var body: some View {
        PortfolioPanelView(
            snapshot: entry.snapshot,
            fontScale: DisplaySettings.fontScale,
            maxRows: rowLimit
        )
            .containerBackground(for: .widget) {
                Color.clear
            }
    }
}

#Preview("Fidelity medium", as: .systemMedium) {
    FidelityPositionsWidget()
} timeline: {
    PositionsEntry(date: .now, snapshot: .placeholder(.fidelity))
}
