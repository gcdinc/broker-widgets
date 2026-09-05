import Foundation

enum FidelityCaptureParser {
    private static let positionArrayKeys: Set<String> = [
        "positiondetail", "positiondetails", "positions", "holdings",
        "topbottompositions", "holdingdetails", "positionlist", "holdinglist"
    ]
    private static let symbolKeys = ["symbol", "ticker", "tickersymbol", "securitysymbol"]
    private static let quantityKeys = [
        "quantity", "qty", "shares", "quantitylong", "sharequantity", "qtylong", "units"
    ]
    private static let lastKeys = ["lastprice", "last", "mark", "closingprice", "closeprice"]
    private static let cautiousLastKeys = ["currentprice", "price"]
    private static let marketKeys = ["marketval", "marketvalue", "mktval", "currentmarketvalue"]
    private static let cautiousMarketKeys = ["currentvalue"]
    private static let nameKeys = ["securitydescription", "name", "description", "securityname"]
    private static let accountKeys = ["acctnum", "accountid", "accountnumber", "acctnumber"]
    private static let dayChangeKeys = ["todaysgainloss", "todaygainloss", "daychange", "daychangevalue"]
    private static let dayPctKeys = ["todaysgainlosspct", "todaysgainlosspercent", "daychangepercent"]

    static func snapshot(from page: CapturedPage) -> PortfolioSnapshot {
        var jsons: [Any] = []
        var fromArrays: [Position] = []

        for item in page.captured {
            guard let text = item.text, let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            jsons.append(json)
            collectFromKnownArrays(json, account: nil, accountName: nil, into: &fromArrays)
        }

        var positions = fromArrays
        if positions.isEmpty {
            for json in jsons {
                collectFromLikelyRows(json, account: nil, accountName: nil, into: &positions)
            }
        }
        let names = accountNames(from: jsons)
        positions = positions.map { position in
            var copy = position
            if copy.accountName == nil, let id = copy.accountId, let name = names[id] {
                copy.accountName = name
            }
            if copy.dayChangePercent == 0 {
                copy.dayChangePercent = copy.resolvedDayChangePercent
            }
            return copy
        }

        if positions.isEmpty, let text = page.text {
            positions.append(contentsOf: parseVisibleText(text))
        }
        // 529 / other Fidelity accounts often have a balance in GetContext
        // but no row in the visible brokerage Positions grid.
        positions.append(contentsOf: accountBalanceHoldings(from: jsons, existing: positions))

        let unique = mergeDuplicates(positions).sorted { $0.resolvedMarketValue > $1.resolvedMarketValue }
        var totalValue = unique.reduce(0) { $0 + $1.resolvedMarketValue }
        var dayChange = unique.reduce(0) { $0 + $1.dayChangeValue }
        var dayPct = totalValue == dayChange ? 0 : (dayChange / (totalValue - dayChange)) * 100
        let context = contextBalance(from: jsons)
        if let context {
            if context.total > totalValue { totalValue = context.total }
            if dayChange == 0 {
                dayChange = context.day
                dayPct = context.pct
            }
        }
        let signedIn = !page.hasPassword && !page.href.localizedCaseInsensitiveContains("login")
        if unique.isEmpty {
            dumpCapturesIfNeeded(page)
            return PortfolioSnapshot(
                broker: .fidelity,
                updatedAt: Date(),
                totalValue: 0,
                dayChangeValue: 0,
                dayChangePercent: 0,
                cash: nil,
                positions: [],
                status: signedIn ? .empty : .needsSignIn,
                message: signedIn
                    ? "Signed in, but no positions were found (\(page.captured.count) captured responses). Stay on Portfolio/Positions, then save session again."
                    : "Sign in to Fidelity in Broker Widgets"
            )
        }
        return PortfolioSnapshot(
            broker: .fidelity,
            updatedAt: Date(),
            totalValue: totalValue,
            dayChangeValue: dayChange,
            dayChangePercent: dayPct,
            cash: nil,
            positions: unique,
            status: .ok,
            message: nil,
            accountMoves: accountMoves(from: jsons)
        )
    }

    /// Same symbol+quantity listed twice (once with an account id, once without) is one holding.
    static func mergeDuplicates(_ positions: [Position]) -> [Position] {
        let sane = positions.filter(isPlausibleHolding)
        func qtyKey(_ quantity: Double) -> String {
            String(format: "%.4f", quantity)
        }

        let groups = Dictionary(grouping: sane) { "\($0.symbol)|\(qtyKey($0.quantity))" }
        return groups.values.flatMap { rows -> [Position] in
            let withAccount = rows.filter { !($0.accountId ?? "").isEmpty }
            let source = withAccount.isEmpty ? rows : withAccount
            let byAccount = Dictionary(grouping: source) { $0.accountId ?? "" }
            let distinctAccounts = byAccount.keys.filter { !$0.isEmpty }
            if distinctAccounts.count > 1 {
                return byAccount.map { pickBest($0.value) }
            }
            return [pickBest(source)]
        }
    }

    static func isPlausibleHolding(_ position: Position) -> Bool {
        let symbol = position.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isTicker(symbol) else { return false }
        guard position.quantity > 0, position.quantity < 10_000_000 else { return false }
        if quantityMatchesSymbolDigits(symbol, quantity: position.quantity) { return false }
        let last = position.lastPrice
        if last < 0 || last >= 1_000_000 { return false }
        if looksLikeAccountNumber(last) { return false }
        let value = position.resolvedMarketValue
        if value <= 0 || value > 20_000_000 { return false }
        if looksLikeAccountNumber(value) { return false }
        if last > 0, position.quantity > 0 {
            let implied = value / position.quantity
            if implied >= 1_000_000 || looksLikeAccountNumber(implied) { return false }
        }
        return true
    }

    private static func isTicker(_ symbol: String) -> Bool {
        if isAccountNumber(symbol) { return false }
        guard symbol.count >= 1, symbol.count <= 10 else { return false }
        return symbol.range(of: "^[A-Z][A-Z0-9./-]{0,9}$", options: .regularExpression) != nil
    }

    private static func isAccountNumber(_ symbol: String) -> Bool {
        if symbol.range(of: "^Z\\d{6,}$", options: .regularExpression) != nil { return true }
        if symbol.range(of: "^\\d{7,}$", options: .regularExpression) != nil { return true }
        return false
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

    private static func pickBest(_ rows: [Position]) -> Position {
        rows.max { lhs, rhs in
            score(lhs) < score(rhs)
        } ?? rows[0]
    }

    private static func score(_ position: Position) -> Double {
        var score = 0.0
        if position.dayChangeValue != 0 { score += 1_000 }
        if position.accountId?.isEmpty == false { score += 100 }
        if position.name != position.symbol { score += 50 }
        if position.lastPrice > 0, position.lastPrice < 10_000 { score += 25 }
        return score
    }

    private static func collectFromKnownArrays(_ node: Any, account: String?, accountName: String?, into positions: inout [Position]) {
        if let array = node as? [Any] {
            array.forEach { collectFromKnownArrays($0, account: account, accountName: accountName, into: &positions) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        let acct = firstString(object, accountKeys) ?? account
        let name = preferenceAccountName(from: object) ?? accountName

        for (key, value) in object {
            if isKnownPositionArrayKey(key), let rows = value as? [Any] {
                for row in rows {
                    if let position = parsePositionRow(row, account: acct, accountName: name) {
                        positions.append(position)
                    }
                    collectFromKnownArrays(row, account: acct, accountName: name, into: &positions)
                }
            } else {
                collectFromKnownArrays(value, account: acct, accountName: name, into: &positions)
            }
        }
    }

    private static func collectFromLikelyRows(_ node: Any, account: String?, accountName: String?, into positions: inout [Position]) {
        if let array = node as? [Any] {
            array.forEach { collectFromLikelyRows($0, account: account, accountName: accountName, into: &positions) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        let acct = firstString(object, accountKeys) ?? account
        let name = preferenceAccountName(from: object) ?? accountName
        if looksLikePositionRow(object), let position = parsePositionRow(object, account: acct, accountName: name) {
            positions.append(position)
        }
        for (_, value) in object {
            collectFromLikelyRows(value, account: acct, accountName: name, into: &positions)
        }
    }

    private static func preferenceAccountName(from object: [String: Any]) -> String? {
        let preference = nested(object, ["preferencedetail"])
        return string(preference["name"]) ?? firstString(object, ["accountname", "acctname", "nickname"])
    }

    private static func contextBalance(from jsons: [Any]) -> (total: Double, day: Double, pct: Double)? {
        for json in jsons {
            guard let root = json as? [String: Any] else { continue }
            let ctx = (root["getContext"] as? [String: Any]) ?? keyed(root)["getcontext"] as? [String: Any] ?? [:]
            let person = nested(ctx, ["person"])
            let gl = nested(nested(nested(person, ["balances"]), ["balancedetail"]), ["gainlossbalancedetail"])
            let total = number(gl["fidelitytotalmktval"]) != 0
                ? number(gl["fidelitytotalmktval"])
                : number(gl["totalmarketval"])
            let day = number(gl["todaysgainloss"])
            let pct = number(gl["todaysgainlosspct"])
            if total > 0 { return (total, day, pct) }
        }
        return nil
    }

    private static func accountMoves(from jsons: [Any]) -> [AccountDayMove] {
        var moves: [String: AccountDayMove] = [:]
        func walk(_ node: Any) {
            if let array = node as? [Any] {
                array.forEach(walk)
                return
            }
            guard let object = node as? [String: Any] else { return }
            if let id = firstString(object, accountKeys) {
                let gl = nested(object, ["gainlossbalancedetail"])
                let day = number(gl["todaysgainloss"])
                let pct = number(gl["todaysgainlosspct"])
                if day != 0 || pct != 0 {
                    moves[id] = AccountDayMove(accountId: id, dayChangeValue: day, dayChangePercent: pct)
                }
            }
            object.values.forEach(walk)
        }
        jsons.forEach(walk)
        return Array(moves.values)
    }

    private static func accountBalanceHoldings(from jsons: [Any], existing: [Position]) -> [Position] {
        let alreadyHave = Set(existing.compactMap(\.accountId))
        var extra: [Position] = []
        for json in jsons {
            guard let root = json as? [String: Any] else { continue }
            let ctx = (root["getContext"] as? [String: Any]) ?? keyed(root)["getcontext"] as? [String: Any] ?? [:]
            let person = nested(ctx, ["person"])
            let assets = (person["assets"] as? [Any]) ?? []
            for asset in assets {
                guard let object = asset as? [String: Any] else { continue }
                guard let id = firstString(object, accountKeys), !alreadyHave.contains(id) else { continue }
                if firstString(object, ["accttype"]) == "External" { continue }
                let gl = nested(object, ["gainlossbalancedetail"])
                let value = number(gl["totalmarketval"])
                guard value > 1 else { continue }
                let name = preferenceAccountName(from: object) ?? "Account"
                let subtype = firstString(object, ["acctsubtype"]) ?? ""
                let day = number(gl["todaysgainloss"])
                let pct = number(gl["todaysgainlosspct"])
                let position = Position(
                    symbol: fallbackSymbol(name: name, subtype: subtype),
                    name: name,
                    quantity: 1,
                    lastPrice: value,
                    marketValue: value,
                    dayChangeValue: day,
                    dayChangePercent: pct,
                    accountId: id,
                    accountName: name
                )
                if isPlausibleHolding(position) {
                    extra.append(position)
                }
            }
        }
        return extra
    }

    private static func fallbackSymbol(name: String, subtype: String) -> String {
        let blob = "\(name) \(subtype)".uppercased()
        if blob.contains("529") || blob.contains("COLLEGE") {
            return "CT529"
        }
        let compact = name.uppercased().filter { $0.isLetter || $0.isNumber }
        let clipped = String(compact.prefix(8))
        if isTicker(clipped) {
            return clipped
        }
        return "HOLDING"
    }

    private static func accountNames(from jsons: [Any]) -> [String: String] {
        var names: [String: String] = [:]
        func walk(_ node: Any) {
            if let array = node as? [Any] {
                array.forEach(walk)
                return
            }
            guard let object = node as? [String: Any] else { return }
            if let id = firstString(object, accountKeys), let name = preferenceAccountName(from: object) {
                names[id] = name
            }
            object.values.forEach(walk)
        }
        jsons.forEach(walk)
        return names
    }

    private static func isKnownPositionArrayKey(_ key: String) -> Bool {
        positionArrayKeys.contains(key.lowercased())
    }

    private static func looksLikePositionRow(_ object: [String: Any]) -> Bool {
        let object = expandedRow(object)
        guard let symbol = firstString(object, symbolKeys), isTicker(symbol.uppercased()) else {
            return false
        }
        guard firstNumber(object, quantityKeys) > 0 else { return false }
        let hasMarket = firstSaneMarket(object) > 0
        let hasLast = firstSaneLast(object) > 0
        let hasName = firstString(object, nameKeys) != nil
        return hasMarket || hasLast || hasName
    }

    private static func parsePositionRow(_ node: Any, account: String?, accountName: String?) -> Position? {
        guard let raw = node as? [String: Any] else { return nil }
        let object = expandedRow(raw)
        guard let symbol = firstString(object, symbolKeys) else { return nil }
        let quantity = firstNumber(object, quantityKeys)
        let market = firstSaneMarket(object)
        let last = firstSaneLast(object)
        let value = market == 0 && quantity != 0 && last != 0 ? quantity * last : market
        let resolvedLast = last == 0 && quantity != 0 && value != 0 ? value / quantity : last
        let acct = firstString(object, accountKeys) ?? account
        let day = firstNumber(object, dayChangeKeys)
        var pct = firstNumber(object, dayPctKeys)
        if pct == 0, day != 0, value != 0 {
            let prior = value - day
            pct = prior == 0 ? 0 : (day / prior) * 100
        }
        let position = Position(
            symbol: symbol.uppercased(),
            name: firstString(object, nameKeys) ?? symbol.uppercased(),
            quantity: quantity,
            lastPrice: resolvedLast,
            marketValue: value,
            dayChangeValue: day,
            dayChangePercent: pct,
            accountId: acct,
            accountName: preferenceAccountName(from: object) ?? accountName
        )
        return isPlausibleHolding(position) ? position : nil
    }

    private static func firstSaneLast(_ object: [String: Any]) -> Double {
        let preferred = firstNumber(object, lastKeys)
        if preferred > 0, preferred < 1_000_000, !looksLikeAccountNumber(preferred) {
            return preferred
        }
        let cautious = firstNumber(object, cautiousLastKeys)
        if cautious > 0, cautious < 100_000, !looksLikeAccountNumber(cautious) {
            return cautious
        }
        return 0
    }

    private static func firstSaneMarket(_ object: [String: Any]) -> Double {
        let nestedMarket = number(nested(object, ["marketvaldetail", "marketvaluedetail"])["marketval"])
        let preferred = firstNumber(object, marketKeys)
        let value = preferred > 0 ? preferred : nestedMarket
        if value > 0, value <= 20_000_000, !looksLikeAccountNumber(value) {
            return value
        }
        let cautious = firstNumber(object, cautiousMarketKeys)
        if cautious > 0, cautious <= 20_000_000, !looksLikeAccountNumber(cautious) {
            return cautious
        }
        return 0
    }

    private static func parseVisibleText(_ text: String) -> [Position] {
        var positions: [Position] = []
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let loneTicker = try? NSRegularExpression(pattern: "^[A-Z][A-Z0-9./-]{0,9}$")
        let leadingTicker = try? NSRegularExpression(pattern: "^([A-Z][A-Z0-9./-]{0,9})\\b")
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            var symbol: String?
            var numbers: [Double] = []
            if let loneTicker, loneTicker.firstMatch(in: line, range: range) != nil {
                symbol = line
                numbers = lines[index..<min(index + 6, lines.count)].compactMap { moneyValue($0) }
            } else if let leadingTicker, let match = leadingTicker.firstMatch(in: line, range: range),
                      let symbolRange = Range(match.range(at: 1), in: line) {
                symbol = String(line[symbolRange])
                numbers = line.split(whereSeparator: { $0.isWhitespace }).compactMap { moneyValue(String($0)) }
            }
            guard let symbol, numbers.count >= 2 else { continue }
            let position = Position(
                symbol: symbol,
                name: symbol,
                quantity: numbers[0],
                lastPrice: numbers[1],
                marketValue: numbers.count > 2 ? numbers[2] : numbers[0] * numbers[1],
                dayChangeValue: numbers.count > 3 ? numbers[3] : 0,
                dayChangePercent: 0
            )
            if isPlausibleHolding(position) {
                positions.append(position)
            }
        }
        return positions
    }

    private static func expandedRow(_ object: [String: Any]) -> [String: Any] {
        var merged = object
        let map = keyed(object)
        for nest in ["instrument", "security", "position", "quote", "securitydetail"] {
            if let nested = map[nest] as? [String: Any] {
                for (key, value) in nested where merged[key] == nil {
                    merged[key] = value
                }
            }
        }
        return merged
    }

    private static func dumpCapturesIfNeeded(_ page: CapturedPage) {
        guard let dir = SnapshotStore.containerURL() else { return }
        let payload: [[String: String]] = page.captured.prefix(8).map { item in
            [
                "url": item.url ?? "",
                "text": String((item.text ?? "").prefix(80_000))
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: dir.appendingPathComponent("fidelity-last-capture.json"), options: .atomic)
    }

    private static func firstString(_ object: [String: Any], _ keys: [String]) -> String? {
        let map = keyed(object)
        for key in keys {
            if let value = string(unwrap(map[key])) {
                return value
            }
        }
        return nil
    }

    private static func firstNumber(_ object: [String: Any], _ keys: [String]) -> Double {
        let map = keyed(object)
        for key in keys {
            let value = number(unwrap(map[key]))
            if value != 0 {
                return value
            }
        }
        return 0
    }

    private static func unwrap(_ raw: Any?) -> Any? {
        guard let object = raw as? [String: Any] else { return raw }
        let map = keyed(object)
        return map["value"] ?? map["amount"] ?? raw
    }

    private static func keyed(_ object: [String: Any]) -> [String: Any] {
        var map: [String: Any] = [:]
        for (key, value) in object {
            map[key.lowercased()] = value
        }
        return map
    }

    private static func nested(_ object: [String: Any], _ keys: [String]) -> [String: Any] {
        let map = keyed(object)
        for key in keys {
            if let nested = map[key] as? [String: Any] {
                return keyed(nested)
            }
        }
        return [:]
    }

    private static func string(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil,
               !trimmed.contains("$") {
                return 0
            }
            return moneyValue(trimmed) ?? 0
        }
        return 0
    }

    private static func moneyValue(_ raw: String) -> Double? {
        let neg = raw.contains("(") || raw.trimmingCharacters(in: .whitespaces).hasPrefix("-")
        let cleaned = raw.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(cleaned), value > 0 || cleaned.contains(".") else { return nil }
        return neg ? -value : value
    }
}
