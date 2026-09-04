import Foundation

enum MoneyFormat {
    private static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    private static let signedCurrency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.positivePrefix = "+" + (f.currencySymbol ?? "$")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.positivePrefix = "+"
        return f
    }()

    private static let shares: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 4
        return f
    }()

    static func usd(_ value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func signedUsd(_ value: Double) -> String {
        if value == 0 { return currency.string(from: NSNumber(value: 0)) ?? "$0.00" }
        return signedCurrency.string(from: NSNumber(value: value)) ?? String(format: "%@%.2f", value > 0 ? "+$" : "-$", abs(value))
    }

    static func percent(_ value: Double) -> String {
        percentFormatter.string(from: NSNumber(value: value / 100.0)) ?? String(format: "%+.2f%%", value)
    }

    static func quantity(_ value: Double) -> String {
        shares.string(from: NSNumber(value: value)) ?? String(value)
    }
}
