import Foundation

enum MarketQuotes {
    static func fillDayChanges(_ positions: [Position]) async -> [Position] {
        let missing = positions.filter {
            $0.dayChangePercent == 0 && $0.symbol.uppercased() != "SPAXX"
        }
        let symbols = Array(Set(missing.map(\.symbol)))
        guard !symbols.isEmpty else { return positions }

        var quotes: [String: (change: Double, percent: Double)] = [:]
        await withTaskGroup(of: (String, Double, Double)?.self) { group in
            for symbol in symbols {
                group.addTask { await quote(for: symbol) }
            }
            for await item in group {
                if let item {
                    quotes[item.0] = (item.1, item.2)
                }
            }
        }

        return positions.map { position in
            guard position.dayChangePercent == 0, let quote = quotes[position.symbol] else {
                return position
            }
            var copy = position
            copy.dayChangePercent = quote.percent
            if position.quantity != 0, quote.change != 0 {
                copy.dayChangeValue = position.quantity * quote.change
            } else {
                copy.dayChangeValue = position.resolvedMarketValue * quote.percent / 100
            }
            return copy
        }
    }

    private static func quote(for symbol: String) async -> (String, Double, Double)? {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let urls = [
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=5d&interval=1d",
            "https://query2.finance.yahoo.com/v8/finance/chart/\(encoded)?range=5d&interval=1d"
        ]
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsed = parseChart(json) else {
                continue
            }
            return (symbol, parsed.change, parsed.percent)
        }
        return nil
    }

    private static func parseChart(_ json: [String: Any]) -> (change: Double, percent: Double)? {
        let chart = json["chart"] as? [String: Any] ?? [:]
        let result = (chart["result"] as? [Any])?.first as? [String: Any] ?? [:]
        let meta = result["meta"] as? [String: Any] ?? [:]
        let price = number(meta["regularMarketPrice"])
        let previous = number(meta["chartPreviousClose"]) != 0
            ? number(meta["chartPreviousClose"])
            : number(meta["previousClose"])
        if let change = meta["regularMarketChange"] as? NSNumber,
           let percent = meta["regularMarketChangePercent"] as? NSNumber {
            return (change.doubleValue, percent.doubleValue)
        }
        if price != 0, previous != 0 {
            let change = price - previous
            return (change, (change / previous) * 100)
        }
        let closes = dailyCloses(result)
        guard closes.count >= 2 else { return nil }
        let last = closes[closes.count - 1]
        let prior = closes[closes.count - 2]
        guard prior != 0 else { return nil }
        let change = last - prior
        return (change, (change / prior) * 100)
    }

    private static func dailyCloses(_ result: [String: Any]) -> [Double] {
        let indicators = result["indicators"] as? [String: Any] ?? [:]
        let quote = (indicators["quote"] as? [Any])?.first as? [String: Any] ?? [:]
        let closes = quote["close"] as? [Any] ?? []
        return closes.compactMap { value -> Double? in
            if value is NSNull { return nil }
            let number = number(value)
            return number == 0 ? nil : number
        }
    }

    private static func number(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) ?? 0 }
        return 0
    }
}
