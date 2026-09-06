import Foundation

enum FidelityCaptureParser {
    static func snapshot(from page: CapturedPage) -> PortfolioSnapshot {
        let decoded = decode(page.captured)
        var positions = decoded.flatMap { FidelityPositionWalk.collectKnown($0, account: nil, accountName: nil) }
        if positions.isEmpty {
            positions = decoded.flatMap { FidelityPositionWalk.collectLikely($0, account: nil, accountName: nil) }
        }
        positions = named(positions, using: FidelityPositionWalk.accountNames(from: decoded))
        if positions.isEmpty, let text = page.text {
            positions.append(contentsOf: FidelityPositionWalk.parseVisibleText(text))
        }
        positions.append(contentsOf: FidelityPositionWalk.workplaceHoldings(from: decoded, existing: positions))

        let unique = FidelityHoldingRules.mergeDuplicates(positions)
            .sorted { $0.resolvedMarketValue > $1.resolvedMarketValue }
        if unique.isEmpty {
            return emptySnapshot(from: page)
        }
        let totals = totals(for: unique, context: FidelityPositionWalk.contextBalance(from: decoded))
        return PortfolioSnapshot(
            broker: .fidelity,
            updatedAt: Date(),
            totalValue: totals.value,
            dayChangeValue: totals.day,
            dayChangePercent: totals.percent,
            cash: nil,
            positions: unique,
            status: .ok,
            message: nil,
            accountMoves: FidelityPositionWalk.accountMoves(from: decoded)
        )
    }

    private static func decode(_ captured: [CapturedNetwork]) -> [Any] {
        captured.compactMap { item in
            guard let text = item.text, let data = text.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private static func named(_ positions: [Position], using names: [String: String]) -> [Position] {
        positions.map { position in
            var copy = position
            if copy.accountName == nil, let id = copy.accountId {
                copy.accountName = names[id]
            }
            if copy.dayChangePercent == 0 {
                copy.dayChangePercent = copy.resolvedDayChangePercent
            }
            return copy
        }
    }

    private static func totals(
        for positions: [Position],
        context: (total: Double, day: Double, pct: Double)?
    ) -> (value: Double, day: Double, percent: Double) {
        var value = positions.reduce(0) { $0 + $1.resolvedMarketValue }
        var day = positions.reduce(0) { $0 + $1.dayChangeValue }
        var percent = Position.dayPercent(change: day, value: value)
        if let context {
            if context.total > value { value = context.total }
            if day == 0 {
                day = context.day
                percent = context.pct
            }
        }
        return (value, day, percent)
    }

    private static func emptySnapshot(from page: CapturedPage) -> PortfolioSnapshot {
        dumpCaptures(page)
        let signedIn = !page.hasPassword && !page.href.localizedCaseInsensitiveContains("login")
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

    private static func dumpCaptures(_ page: CapturedPage) {
        guard let dir = SnapshotStore.containerURL() else { return }
        let payload: [[String: String]] = page.captured.prefix(8).map { item in
            ["url": item.url ?? "", "text": String((item.text ?? "").prefix(80_000))]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: dir.appendingPathComponent("fidelity-last-capture.json"), options: .atomic)
    }
}
