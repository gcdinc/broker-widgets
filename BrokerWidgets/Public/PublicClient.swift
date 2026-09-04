import Foundation

enum PublicClient {
    private static let authURL = URL(string: "https://api.public.com/userapiauthservice/personal/access-tokens")!
    private static let accountsURL = URL(string: "https://api.public.com/userapigateway/trading/account")!

    static func fetchSnapshot(secret: String) async throws -> PortfolioSnapshot {
        let token = try await accessToken(secret: secret)
        let accounts = try await request(accountsURL, token: token, as: PublicAccountsResponse.self).accounts
        guard !accounts.isEmpty else {
            throw PublicClientError.noAccounts
        }

        var allPositions: [Position] = []
        var totalValue: Double = 0
        var cash: Double = 0
        var dayChange: Double = 0

        for account in accounts {
            let url = URL(string: "https://api.public.com/userapigateway/trading/\(account.accountId)/portfolio/v2")!
            let portfolio = try await request(url, token: token, as: PublicPortfolio.self)
            totalValue += parseDouble(portfolio.totalAccountValue)
            cash += parseDouble(portfolio.cash)
            for raw in portfolio.positions ?? [] {
                let position = raw.asPosition(accountId: account.accountId)
                allPositions.append(position)
                dayChange += position.dayChangeValue
            }
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
            message: status == .empty ? "No Public positions yet" : nil
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
        struct TokenResponse: Decodable {
            let accessToken: String
        }

        let body = try JSONEncoder().encode(Body(validityInMinutes: 60, secret: secret))
        let response: TokenResponse = try await request(authURL, token: nil, method: "POST", body: body)
        let cached = CachedToken(accessToken: response.accessToken, expiresAt: Date().addingTimeInterval(50 * 60))
        if let data = try? JSONEncoder().encode(cached) {
            try? KeychainStore.setData(data, for: .publicToken)
        }
        return response.accessToken
    }

    private static func loadCachedToken() -> CachedToken? {
        guard let data = KeychainStore.getData(.publicToken) else { return nil }
        return try? JSONDecoder().decode(CachedToken.self, from: data)
    }

    private static func request<T: Decodable>(
        _ url: URL,
        token: String?,
        method: String = "GET",
        body: Data? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BrokerWidgets/1.0", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if status == 401 {
                KeychainStore.delete(.publicToken)
            }
            throw PublicClientError.http(status, text)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

private struct CachedToken: Codable {
    var accessToken: String
    var expiresAt: Date
}

private struct PublicAccountsResponse: Decodable {
    var accounts: [PublicAccount]
}

private struct PublicAccount: Decodable {
    var accountId: String
}

private struct PublicPortfolio: Decodable {
    var totalAccountValue: String?
    var cash: String?
    var positions: [PublicPositionDTO]?
}

private struct PublicPositionDTO: Decodable {
    var instrument: PublicInstrument
    var quantity: String?
    var currentValue: String?
    var lastPrice: PublicLastPrice?
    var instrumentGain: PublicGain?
    var positionDailyGain: PublicGain?
    var costBasis: PublicCostBasis?

    func asPosition(accountId: String) -> Position {
        let qty = parseDouble(quantity)
        let last = parseDouble(lastPrice?.lastPrice)
        let value = parseDouble(currentValue)
        return Position(
            symbol: instrument.symbol,
            name: instrument.name ?? instrument.symbol,
            quantity: qty,
            lastPrice: last,
            marketValue: value == 0 ? qty * last : value,
            dayChangeValue: parseDouble(positionDailyGain?.gainValue),
            dayChangePercent: parseDouble(positionDailyGain?.gainPercentage),
            totalGainValue: parseDouble(costBasis?.gainValue ?? instrumentGain?.gainValue),
            totalGainPercent: parseDouble(costBasis?.gainPercentage ?? instrumentGain?.gainPercentage),
            accountId: accountId
        )
    }
}

private struct PublicInstrument: Decodable {
    var symbol: String
    var name: String?
    var type: String?
}

private struct PublicLastPrice: Decodable {
    var lastPrice: String?
}

private struct PublicGain: Decodable {
    var gainValue: String?
    var gainPercentage: String?
}

private struct PublicCostBasis: Decodable {
    var gainValue: String?
    var gainPercentage: String?
}

private func parseDouble(_ raw: String?) -> Double {
    guard let raw else { return 0 }
    let cleaned = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
    return Double(cleaned) ?? 0
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
            return "Public.com HTTP \(code): \(body.prefix(180))"
        }
    }
}
