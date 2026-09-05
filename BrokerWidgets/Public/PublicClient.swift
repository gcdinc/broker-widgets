import Foundation

enum PublicClient {
    private static let authURL = URL(string: "https://api.public.com/userapiauthservice/personal/access-tokens")!
    private static let accountsURL = URL(string: "https://api.public.com/userapigateway/trading/account")!

    static func fetchSnapshot(secret: String) async throws -> PortfolioSnapshot {
        let token = try await accessToken(secret: secret)
        let accountsJSON = try await requestJSON(accountsURL, token: token)
        let accounts = extractAccounts(accountsJSON)
        guard !accounts.isEmpty else {
            throw PublicClientError.noAccounts
        }

        var allPositions: [Position] = []
        var totalValue: Double = 0
        var cash: Double = 0
        var dayChange: Double = 0
        var accountMoves: [AccountDayMove] = []

        for account in accounts {
            let url = URL(string: "https://api.public.com/userapigateway/trading/\(account.id)/portfolio/v2")!
            let portfolio = try await requestJSON(url, token: token)
            totalValue += JSONNumber.double(portfolio["totalAccountValue"])
            cash += JSONNumber.double(portfolio["cash"])
            let type = (portfolio["accountType"] as? String) ?? account.type
            let name = PublicAccount.displayName(type: type, brokerageType: account.brokerageType)
            let rows = portfolio["positions"] as? [Any] ?? []
            var accountDay = 0.0
            var accountValue = 0.0
            for row in rows {
                guard var position = parsePosition(row, accountId: account.id) else { continue }
                position.accountName = name
                allPositions.append(position)
                dayChange += position.dayChangeValue
                accountDay += position.dayChangeValue
                accountValue += position.resolvedMarketValue
            }
            let prior = accountValue - accountDay
            accountMoves.append(
                AccountDayMove(
                    accountId: account.id,
                    dayChangeValue: accountDay,
                    dayChangePercent: prior == 0 ? 0 : (accountDay / prior) * 100
                )
            )
        }

        allPositions.sort { $0.resolvedMarketValue > $1.resolvedMarketValue }
        let prior = totalValue - dayChange
        let dayPct = prior == 0 ? 0 : (dayChange / prior) * 100
        let status: SnapshotStatus = allPositions.isEmpty && totalValue == 0 ? .empty : .ok
        return PortfolioSnapshot(
            broker: .publicBroker,
            updatedAt: Date(),
            totalValue: totalValue,
            dayChangeValue: dayChange,
            dayChangePercent: dayPct,
            cash: cash,
            positions: allPositions,
            status: status,
            message: status == .empty ? "No Public positions yet" : nil,
            accountMoves: accountMoves
        )
    }

    private static func accessToken(secret: String) async throws -> String {
        if let cached = loadCachedToken(), cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.accessToken
        }

        struct Body: Encodable {
            let validityInMinutes: Int
            let secret: String
        }

        let body = try JSONEncoder().encode(Body(validityInMinutes: 60, secret: secret))
        let json = try await requestJSON(authURL, token: nil, method: "POST", body: body)
        guard let token = json["accessToken"] as? String ?? json["access_token"] as? String else {
            throw PublicClientError.http(200, "Token response missing accessToken: \(json.keys.sorted())")
        }
        let cached = CachedToken(accessToken: token, expiresAt: Date().addingTimeInterval(50 * 60))
        if let data = try? JSONEncoder().encode(cached) {
            try? KeychainStore.setData(data, for: .publicToken)
        }
        return token
    }

    private static func loadCachedToken() -> CachedToken? {
        guard let data = KeychainStore.getData(.publicToken) else { return nil }
        return try? JSONDecoder().decode(CachedToken.self, from: data)
    }

    private static func requestJSON(
        _ url: URL,
        token: String?,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BrokerWidgets/1.0", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            if status == 401 {
                KeychainStore.delete(.publicToken)
            }
            throw PublicClientError.http(status, text)
        }
        let parsed = try JSONSerialization.jsonObject(with: data)
        if let object = parsed as? [String: Any] {
            return object
        }
        if let array = parsed as? [Any] {
            return ["accounts": array]
        }
        throw PublicClientError.http(status, "Unexpected JSON root")
    }

    private static func extractAccounts(_ json: [String: Any]) -> [PublicAccount] {
        let rows = json["accounts"] as? [Any] ?? []
        return rows.compactMap { row in
            guard let object = row as? [String: Any] else { return nil }
            guard let id = (object["accountId"] as? String) ?? (object["account_id"] as? String) else {
                return nil
            }
            return PublicAccount(
                id: id,
                type: (object["accountType"] as? String) ?? (object["account_type"] as? String),
                brokerageType: (object["brokerageAccountType"] as? String) ?? (object["brokerage_account_type"] as? String)
            )
        }
    }

    private static func parsePosition(_ raw: Any, accountId: String) -> Position? {
        guard let object = raw as? [String: Any] else { return nil }
        let instrument = object["instrument"] as? [String: Any] ?? [:]
        guard let symbol = (instrument["symbol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !symbol.isEmpty else {
            return nil
        }
        let lastPriceObject = object["lastPrice"] as? [String: Any]
        let daily = object["positionDailyGain"] as? [String: Any]
        let cost = object["costBasis"] as? [String: Any]
        let instrumentGain = object["instrumentGain"] as? [String: Any]
        let qty = JSONNumber.double(object["quantity"])
        let last = JSONNumber.double(lastPriceObject?["lastPrice"] ?? object["lastPrice"])
        let value = JSONNumber.double(object["currentValue"])
        return Position(
            symbol: symbol,
            name: (instrument["name"] as? String) ?? symbol,
            quantity: qty,
            lastPrice: last,
            marketValue: value == 0 ? qty * last : value,
            dayChangeValue: JSONNumber.double(daily?["gainValue"]),
            dayChangePercent: JSONNumber.double(daily?["gainPercentage"]),
            totalGainValue: JSONNumber.double(cost?["gainValue"] ?? instrumentGain?["gainValue"]),
            totalGainPercent: JSONNumber.double(cost?["gainPercentage"] ?? instrumentGain?["gainPercentage"]),
            accountId: accountId
        )
    }
}

private struct PublicAccount {
    var id: String
    var type: String?
    var brokerageType: String?

    static func displayName(type: String?, brokerageType: String?) -> String {
        switch type?.uppercased() {
        case "BROKERAGE":
            if brokerageType?.uppercased() == "MARGIN" { return "Brokerage · Margin" }
            return "Brokerage"
        case "BOND_ACCOUNT":
            return "Bonds"
        case "HIGH_YIELD":
            return "High yield"
        case "TREASURY":
            return "Treasury"
        case "TRADITIONAL_IRA":
            return "Traditional IRA"
        case "ROTH_IRA":
            return "Roth IRA"
        case "ENTITY":
            return "Entity"
        case "RIA_ASSET":
            return "Managed"
        case let raw?:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return "Account"
        }
    }
}

private struct CachedToken: Codable {
    var accessToken: String
    var expiresAt: Date
}

private enum JSONNumber {
    static func double(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String {
            let cleaned = value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            return Double(cleaned) ?? 0
        }
        return 0
    }
}

enum PublicClientError: LocalizedError {
    case noAccounts
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAccounts:
            return "No Public.com accounts on this API key."
        case .http(let code, let body):
            if code == 401 { return "Public.com rejected the API secret." }
            let snippet = body.replacingOccurrences(of: "\n", with: " ").prefix(180)
            return "Public.com HTTP \(code): \(snippet)"
        }
    }
}
