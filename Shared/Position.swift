import Foundation

struct Position: Codable, Identifiable, Hashable {
    var symbol: String
    var name: String
    var quantity: Double
    var lastPrice: Double
    var marketValue: Double
    var dayChangeValue: Double
    var dayChangePercent: Double
    var totalGainValue: Double?
    var totalGainPercent: Double?
    var accountId: String?

    var id: String {
        "\(accountId ?? "")|\(symbol)"
    }

    var resolvedMarketValue: Double {
        if marketValue != 0 { return marketValue }
        return quantity * lastPrice
    }
}

enum SnapshotStatus: String, Codable {
    case ok
    case needsSignIn
    case needsSecret
    case error
    case empty
}

struct PortfolioSnapshot: Codable, Equatable {
    var broker: BrokerKind
    var updatedAt: Date
    var totalValue: Double
    var dayChangeValue: Double
    var dayChangePercent: Double
    var cash: Double?
    var positions: [Position]
    var status: SnapshotStatus
    var message: String?

    static func placeholder(_ broker: BrokerKind) -> PortfolioSnapshot {
        PortfolioSnapshot(
            broker: broker,
            updatedAt: Date(),
            totalValue: 125_430.12,
            dayChangeValue: 842.50,
            dayChangePercent: 0.68,
            cash: 1_200,
            positions: [
                Position(symbol: "AAPL", name: "Apple Inc.", quantity: 40, lastPrice: 228.4, marketValue: 9_136, dayChangeValue: 48, dayChangePercent: 0.53),
                Position(symbol: "MSFT", name: "Microsoft", quantity: 20, lastPrice: 430.1, marketValue: 8_602, dayChangeValue: -22, dayChangePercent: -0.25),
                Position(symbol: "VOO", name: "Vanguard S&P 500", quantity: 15, lastPrice: 512.2, marketValue: 7_683, dayChangeValue: 31, dayChangePercent: 0.40)
            ],
            status: .ok,
            message: nil
        )
    }

    static func setup(_ broker: BrokerKind) -> PortfolioSnapshot {
        switch broker {
        case .fidelity:
            return PortfolioSnapshot(
                broker: broker,
                updatedAt: Date(),
                totalValue: 0,
                dayChangeValue: 0,
                dayChangePercent: 0,
                cash: nil,
                positions: [],
                status: .needsSignIn,
                message: "Sign in to Fidelity in Broker Widgets"
            )
        case .publicBroker:
            return PortfolioSnapshot(
                broker: broker,
                updatedAt: Date(),
                totalValue: 0,
                dayChangeValue: 0,
                dayChangePercent: 0,
                cash: nil,
                positions: [],
                status: .needsSecret,
                message: "Add your Public.com API secret in Broker Widgets"
            )
        }
    }
}
