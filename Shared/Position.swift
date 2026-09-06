import Foundation

struct Position: Codable, Identifiable, Hashable {
    var symbol: String
    var name: String
    var quantity: Double
    var lastPrice: Double
    var marketValue: Double
    var dayChangeValue: Double
    var dayChangePercent: Double
    var accountId: String?
    var accountName: String?

    var id: String {
        "\(accountId ?? "")|\(symbol)"
    }

    var resolvedMarketValue: Double {
        if marketValue != 0 { return marketValue }
        return quantity * lastPrice
    }

    var displayAccountName: String {
        if let accountName, !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accountName
        }
        if let accountId, !accountId.isEmpty {
            return accountId
        }
        return "Account"
    }

    var resolvedDayChangePercent: Double {
        if dayChangePercent != 0 { return dayChangePercent }
        return Self.dayPercent(change: dayChangeValue, value: resolvedMarketValue)
    }

    static func dayPercent(change: Double, value: Double, explicit: Double = 0) -> Double {
        if explicit != 0 { return explicit }
        let prior = value - change
        guard change != 0, prior != 0 else { return 0 }
        return (change / prior) * 100
    }

    /// Bonds from Public.com use a CUSIP as `symbol` (e.g. 03770DAD5). Show the coupon name instead.
    var displaySymbol: String {
        if Self.isCusip(symbol) {
            return Self.shortBondLabel(name: name, fallback: symbol)
        }
        return symbol
    }

    private static func isCusip(_ symbol: String) -> Bool {
        symbol.count == 9
            && symbol.range(of: "^[0-9A-Z]{9}$", options: .regularExpression) != nil
            && symbol.contains(where: \.isNumber)
    }

    private static func shortBondLabel(name: String, fallback: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2, parts[1].contains("%") {
            return "\(parts[0]) \(parts[1])"
        }
        if let first = parts.first, (1...6).contains(first.count) {
            return first
        }
        if !name.isEmpty {
            return String(name.prefix(18))
        }
        return fallback
    }
}

struct AccountDayMove: Codable, Hashable {
    var accountId: String
    var dayChangeValue: Double
    var dayChangePercent: Double
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
    var accountMoves: [AccountDayMove]?

    func dayMove(forAccountId accountId: String?) -> AccountDayMove? {
        guard let accountId else { return nil }
        return accountMoves?.first { $0.accountId == accountId }
    }

    static func placeholder(_ broker: BrokerKind) -> PortfolioSnapshot {
        PortfolioSnapshot(
            broker: broker,
            updatedAt: Date(),
            totalValue: 125_430.12,
            dayChangeValue: 842.50,
            dayChangePercent: 0.68,
            cash: 1_200,
            positions: [
                Position(symbol: "AAPL", name: "Apple Inc.", quantity: 40, lastPrice: 228.4, marketValue: 9_136, dayChangeValue: 48, dayChangePercent: 0.53, accountName: "Brokerage"),
                Position(symbol: "MSFT", name: "Microsoft", quantity: 20, lastPrice: 430.1, marketValue: 8_602, dayChangeValue: -22, dayChangePercent: -0.25, accountName: "Brokerage"),
                Position(symbol: "VOO", name: "Vanguard S&P 500", quantity: 15, lastPrice: 512.2, marketValue: 7_683, dayChangeValue: 31, dayChangePercent: 0.40, accountName: "Brokerage")
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
