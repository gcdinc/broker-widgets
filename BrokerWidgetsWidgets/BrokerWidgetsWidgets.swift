import SwiftUI
import WidgetKit

struct PositionsEntry: TimelineEntry {
    let date: Date
    let snapshot: PortfolioSnapshot
}

struct PositionsProvider: TimelineProvider {
    let broker: BrokerKind

    func placeholder(in context: Context) -> PositionsEntry {
        PositionsEntry(date: Date(), snapshot: .placeholder(broker))
    }

    func getSnapshot(in context: Context, completion: @escaping (PositionsEntry) -> Void) {
        let snapshot = SnapshotStore.load(broker) ?? .setup(broker)
        completion(PositionsEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PositionsEntry>) -> Void) {
        let snapshot = SnapshotStore.load(broker) ?? .setup(broker)
        let entry = PositionsEntry(date: Date(), snapshot: snapshot)
        let next = Date().addingTimeInterval(AppConstants.widgetReloadInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FidelityPositionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FidelityPositionsWidget", provider: PositionsProvider(broker: .fidelity)) { entry in
            PositionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Fidelity Positions")
        .description("Holdings from your Fidelity accounts.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PublicPositionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PublicPositionsWidget", provider: PositionsProvider(broker: .publicBroker)) { entry in
            PositionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Public Positions")
        .description("Holdings from your Public.com accounts.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct BrokerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FidelityPositionsWidget()
        PublicPositionsWidget()
    }
}
