import Foundation

enum FidelityPositionWalk {
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
    static let accountKeys = ["acctnum", "accountid", "accountnumber", "acctnumber"]
    private static let dayChangeKeys = ["todaysgainloss", "todaygainloss", "daychange", "daychangevalue"]
    private static let dayPctKeys = ["todaysgainlosspct", "todaysgainlosspercent", "daychangepercent"]

    static func collectKnown(_ node: Any, account: String?, accountName: String?) -> [Position] {
        var positions: [Position] = []
        collectKnown(node, account: account, accountName: accountName, into: &positions)
        return positions
    }

    static func collectLikely(_ node: Any, account: String?, accountName: String?) -> [Position] {
        var positions: [Position] = []
        collectLikely(node, account: account, accountName: accountName, into: &positions)
        return positions
    }

    static func accountNames(from jsons: [Any]) -> [String: String] {
        var names: [String: String] = [:]
        jsons.forEach { json in
            FidelityJSON.walk(json) { object in
                if let id = FidelityJSON.firstString(object, accountKeys),
                   let name = preferenceAccountName(from: object) {
                    names[id] = name
                }
            }
        }
        return names
    }

    static func contextBalance(from jsons: [Any]) -> (total: Double, day: Double, pct: Double)? {
        guard let person = FidelityJSON.getContextPerson(from: jsons) else { return nil }
        let gl = FidelityJSON.nested(
            FidelityJSON.nested(FidelityJSON.nested(person, ["balances"]), ["balancedetail"]),
            ["gainlossbalancedetail"]
        )
        let total = JSONValue.number(gl["fidelitytotalmktval"]).nonZero
            ?? JSONValue.number(gl["totalmarketval"])
        guard total > 0 else { return nil }
        return (total, JSONValue.number(gl["todaysgainloss"]), JSONValue.number(gl["todaysgainlosspct"]))
    }

    static func accountMoves(from jsons: [Any]) -> [AccountDayMove] {
        var moves: [String: AccountDayMove] = [:]
        jsons.forEach { json in
            FidelityJSON.walk(json) { object in
                guard let id = FidelityJSON.firstString(object, accountKeys) else { return }
                let gl = FidelityJSON.nested(object, ["gainlossbalancedetail"])
                let day = JSONValue.number(gl["todaysgainloss"])
                let pct = JSONValue.number(gl["todaysgainlosspct"])
                if day != 0 || pct != 0 {
                    moves[id] = AccountDayMove(accountId: id, dayChangeValue: day, dayChangePercent: pct)
                }
            }
        }
        return Array(moves.values)
    }

    static func workplaceHoldings(from jsons: [Any], existing: [Position]) -> [Position] {
        let alreadyHave = Set(existing.compactMap(\.accountId))
        guard let person = FidelityJSON.getContextPerson(from: jsons) else { return [] }
        let assets = person["assets"] as? [Any] ?? []
        return assets.compactMap { workplaceHolding($0, alreadyHave: alreadyHave) }
    }

    static func parseVisibleText(_ text: String) -> [Position] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.enumerated().compactMap { index, line in
            position(fromVisible: line, following: Array(lines[index..<min(index + 6, lines.count)]))
        }
    }

    static func parsePositionRow(_ node: Any, account: String?, accountName: String?) -> Position? {
        guard let raw = node as? [String: Any] else { return nil }
        let object = expandedRow(raw)
        guard let symbol = FidelityJSON.firstString(object, symbolKeys) else { return nil }
        let quantity = FidelityJSON.firstNumber(object, quantityKeys)
        let market = firstSaneMarket(object)
        let last = firstSaneLast(object)
        let value = market == 0 && quantity != 0 && last != 0 ? quantity * last : market
        let resolvedLast = last == 0 && quantity != 0 && value != 0 ? value / quantity : last
        let day = FidelityJSON.firstNumber(object, dayChangeKeys)
        let position = Position(
            symbol: symbol.uppercased(),
            name: FidelityJSON.firstString(object, nameKeys) ?? symbol.uppercased(),
            quantity: quantity,
            lastPrice: resolvedLast,
            marketValue: value,
            dayChangeValue: day,
            dayChangePercent: Position.dayPercent(
                change: day,
                value: value,
                explicit: FidelityJSON.firstNumber(object, dayPctKeys)
            ),
            accountId: FidelityJSON.firstString(object, accountKeys) ?? account,
            accountName: preferenceAccountName(from: object) ?? accountName
        )
        return FidelityHoldingRules.isPlausibleHolding(position) ? position : nil
    }

    private static func collectKnown(_ node: Any, account: String?, accountName: String?, into positions: inout [Position]) {
        if let array = node as? [Any] {
            array.forEach { collectKnown($0, account: account, accountName: accountName, into: &positions) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        let acct = FidelityJSON.firstString(object, accountKeys) ?? account
        let name = preferenceAccountName(from: object) ?? accountName
        for (key, value) in object {
            appendKnown(key: key, value: value, account: acct, accountName: name, into: &positions)
        }
    }

    private static func appendKnown(
        key: String,
        value: Any,
        account: String?,
        accountName: String?,
        into positions: inout [Position]
    ) {
        guard positionArrayKeys.contains(key.lowercased()), let rows = value as? [Any] else {
            collectKnown(value, account: account, accountName: accountName, into: &positions)
            return
        }
        for row in rows {
            if let position = parsePositionRow(row, account: account, accountName: accountName) {
                positions.append(position)
            }
            collectKnown(row, account: account, accountName: accountName, into: &positions)
        }
    }

    private static func collectLikely(_ node: Any, account: String?, accountName: String?, into positions: inout [Position]) {
        if let array = node as? [Any] {
            array.forEach { collectLikely($0, account: account, accountName: accountName, into: &positions) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        let acct = FidelityJSON.firstString(object, accountKeys) ?? account
        let name = preferenceAccountName(from: object) ?? accountName
        if looksLikePositionRow(object), let position = parsePositionRow(object, account: acct, accountName: name) {
            positions.append(position)
        }
        object.values.forEach { collectLikely($0, account: acct, accountName: name, into: &positions) }
    }

    private static func workplaceHolding(_ asset: Any, alreadyHave: Set<String>) -> Position? {
        guard let object = asset as? [String: Any] else { return nil }
        guard let id = FidelityJSON.firstString(object, accountKeys), !alreadyHave.contains(id) else { return nil }
        if FidelityJSON.firstString(object, ["accttype"]) == "External" { return nil }
        let name = preferenceAccountName(from: object) ?? "Account"
        let subtype = FidelityJSON.firstString(object, ["acctsubtype"]) ?? ""
        let blob = "\(name) \(subtype)".uppercased()
        guard blob.contains("529") || blob.contains("COLLEGE") || blob.contains("WORKPLACE") else { return nil }
        let gl = FidelityJSON.nested(object, ["gainlossbalancedetail"])
        let value = JSONValue.number(gl["totalmarketval"])
        guard value > 1 else { return nil }
        let position = Position(
            symbol: "CT529",
            name: name,
            quantity: 1,
            lastPrice: value,
            marketValue: value,
            dayChangeValue: JSONValue.number(gl["todaysgainloss"]),
            dayChangePercent: JSONValue.number(gl["todaysgainlosspct"]),
            accountId: id,
            accountName: name
        )
        return FidelityHoldingRules.isPlausibleHolding(position) ? position : nil
    }

    private static func preferenceAccountName(from object: [String: Any]) -> String? {
        let preference = FidelityJSON.nested(object, ["preferencedetail"])
        return FidelityJSON.string(preference["name"])
            ?? FidelityJSON.firstString(object, ["accountname", "acctname", "nickname"])
    }

    private static func looksLikePositionRow(_ object: [String: Any]) -> Bool {
        let object = expandedRow(object)
        guard let symbol = FidelityJSON.firstString(object, symbolKeys),
              FidelityHoldingRules.isTicker(symbol.uppercased()) else { return false }
        guard FidelityJSON.firstNumber(object, quantityKeys) > 0 else { return false }
        return firstSaneMarket(object) > 0
            || firstSaneLast(object) > 0
            || FidelityJSON.firstString(object, nameKeys) != nil
    }

    private static func firstSaneLast(_ object: [String: Any]) -> Double {
        let preferred = FidelityJSON.firstNumber(object, lastKeys)
        if FidelityHoldingRules.pricesAgree(last: preferred, quantity: 1, value: preferred) {
            return preferred
        }
        let cautious = FidelityJSON.firstNumber(object, cautiousLastKeys)
        if cautious > 0, cautious < 100_000 {
            return cautious
        }
        return 0
    }

    private static func firstSaneMarket(_ object: [String: Any]) -> Double {
        let nestedMarket = JSONValue.number(
            FidelityJSON.nested(object, ["marketvaldetail", "marketvaluedetail"])["marketval"]
        )
        let preferred = FidelityJSON.firstNumber(object, marketKeys)
        let value = preferred > 0 ? preferred : nestedMarket
        if value > 0, value <= 20_000_000 { return value }
        let cautious = FidelityJSON.firstNumber(object, cautiousMarketKeys)
        return cautious > 0 && cautious <= 20_000_000 ? cautious : 0
    }

    private static func expandedRow(_ object: [String: Any]) -> [String: Any] {
        var merged = object
        let map = FidelityJSON.keyed(object)
        for nest in ["instrument", "security", "position", "quote", "securitydetail"] {
            guard let nested = map[nest] as? [String: Any] else { continue }
            for (key, value) in nested where merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }

    private static let loneSymbol = try? NSRegularExpression(pattern: "^[A-Z][A-Z0-9./-]{1,9}$")
    private static let leadingSymbol = try? NSRegularExpression(pattern: "^([A-Z][A-Z0-9./-]{1,9})\\b")

    private static func position(fromVisible line: String, following: [String]) -> Position? {
        let range = NSRange(line.startIndex..., in: line)
        let lone = loneSymbol
        let leading = leadingSymbol
        var symbol: String?
        var numbers: [Double] = []
        if lone?.firstMatch(in: line, range: range) != nil {
            symbol = line
            numbers = following.compactMap { JSONValue.money($0) }
        } else if let match = leading?.firstMatch(in: line, range: range),
                  let symbolRange = Range(match.range(at: 1), in: line) {
            symbol = String(line[symbolRange])
            numbers = line.split(whereSeparator: { $0.isWhitespace }).compactMap { JSONValue.money(String($0)) }
        }
        guard let symbol, numbers.count >= 2 else { return nil }
        let position = Position(
            symbol: symbol,
            name: symbol,
            quantity: numbers[0],
            lastPrice: numbers[1],
            marketValue: numbers.count > 2 ? numbers[2] : numbers[0] * numbers[1],
            dayChangeValue: numbers.count > 3 ? numbers[3] : 0,
            dayChangePercent: 0
        )
        return FidelityHoldingRules.isPlausibleHolding(position) ? position : nil
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
