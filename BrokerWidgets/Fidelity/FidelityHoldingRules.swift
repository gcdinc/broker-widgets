import Foundation

enum FidelityHoldingRules {
    private static let rejectedSymbols: Set<String> = [
        "HOLDING", "INDIVIDU", "INDIVIDUAL", "BROKERAGE", "ACCOUNT", "ROTH", "TOD",
        "JOINT", "TRUST", "CASH", "TOTAL", "VALUE", "SYMBOL", "QTY", "HIGH", "LOW",
        "OPEN", "CLOSE", "APPLY", "DISMISS", "TIMEFRAME", "DOWNLOAD", "OVERVIEW",
        "SETTINGS", "POSITIONS", "BALANCES", "SECURITY", "RETIREMENT", "ACCOUNTS",
        "MENU", "RETRY", "SUMMARY", "SAVE", "LABEL", "CONSENT", "EDUCATION",
        "PLANNING", "TRANSACT", "OTHER", "CANCEL", "LOADING", "TRANSFER", "PRIVACY",
        "MESSAGES", "TRADE", "DOCUMENTS", "INVESTMENT", "ANALYSIS", "QUOTE", "YIELD",
        "PAGE", "PRINT", "REVIEW", "VIEW", "ERROR", "EX-DATE", "SAVECANCEL", "OF", "TO",
        "ET"
    ]

    static func mergeDuplicates(_ positions: [Position]) -> [Position] {
        let sane = positions.filter(isPlausibleHolding)
        let groups = Dictionary(grouping: sane) { "\($0.symbol)|\(qtyKey($0.quantity))" }
        return groups.values.flatMap(collapseGroup)
    }

    static func isPlausibleHolding(_ position: Position) -> Bool {
        let symbol = position.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isTicker(symbol) else { return false }
        guard isSaneQuantity(position.quantity) else { return false }
        if quantityMatchesSymbolDigits(symbol, quantity: position.quantity) { return false }
        return pricesAgree(
            last: position.lastPrice,
            quantity: position.quantity,
            value: position.resolvedMarketValue
        )
    }

    static func isTicker(_ symbol: String) -> Bool {
        if isAccountNumber(symbol) { return false }
        if rejectedSymbols.contains(symbol) { return false }
        guard (2...10).contains(symbol.count) else { return false }
        return symbol.range(of: "^[A-Z][A-Z0-9./-]{1,9}$", options: .regularExpression) != nil
    }

    static func isSaneQuantity(_ quantity: Double) -> Bool {
        quantity > 0 && quantity < 10_000_000
    }

    static func pricesAgree(last: Double, quantity: Double, value: Double) -> Bool {
        guard last >= 0, last <= 25_000 else { return false }
        if looksLikeYear(last) || looksLikeAccountNumber(last) { return false }
        guard value > 0, value <= 20_000_000 else { return false }
        if looksLikeAccountNumber(value) { return false }
        guard last > 0, quantity > 0 else { return true }
        let implied = value / quantity
        if implied >= 1_000_000 || looksLikeAccountNumber(implied) { return false }
        let ratio = implied / last
        return ratio >= 0.45 && ratio <= 2.2
    }

    private static func collapseGroup(_ rows: [Position]) -> [Position] {
        let withAccount = rows.filter { !($0.accountId ?? "").isEmpty }
        let source = withAccount.isEmpty ? rows : withAccount
        let byAccount = Dictionary(grouping: source) { $0.accountId ?? "" }
        let distinct = byAccount.keys.filter { !$0.isEmpty }
        if distinct.count > 1 {
            return byAccount.map { pickBest($0.value) }
        }
        return [pickBest(source)]
    }

    private static func pickBest(_ rows: [Position]) -> Position {
        rows.max { score($0) < score($1) } ?? rows[0]
    }

    private static func score(_ position: Position) -> Double {
        var score = 0.0
        if position.dayChangeValue != 0 { score += 1_000 }
        if position.accountId?.isEmpty == false { score += 100 }
        if position.name != position.symbol { score += 50 }
        if position.lastPrice > 0, position.lastPrice < 10_000 { score += 25 }
        return score
    }

    private static func qtyKey(_ quantity: Double) -> String {
        String(format: "%.4f", quantity)
    }

    private static func isAccountNumber(_ symbol: String) -> Bool {
        symbol.range(of: "^Z\\d{6,}$", options: .regularExpression) != nil
            || symbol.range(of: "^\\d{7,}$", options: .regularExpression) != nil
    }

    private static func looksLikeYear(_ value: Double) -> Bool {
        value >= 1900 && value <= 2100 && abs(value.rounded() - value) < 0.001
    }

    private static func looksLikeAccountNumber(_ value: Double) -> Bool {
        guard value >= 1_000_000, abs(value.rounded() - value) < 0.001 else { return false }
        return String(Int(value.rounded())).count >= 7
    }

    private static func quantityMatchesSymbolDigits(_ symbol: String, quantity: Double) -> Bool {
        let digits = symbol.filter(\.isNumber)
        guard digits.count >= 6, let id = Double(digits) else { return false }
        return abs(id - quantity) < 1
    }
}
