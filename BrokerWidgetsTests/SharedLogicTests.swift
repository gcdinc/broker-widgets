import AppKit
import XCTest
@testable import BrokerWidgets

final class SharedLogicTests: XCTestCase {
    func testDayPercentBranches() {
        XCTAssertEqual(Position.dayPercent(change: 10, value: 110), 10, accuracy: 0.001)
        XCTAssertEqual(Position.dayPercent(change: 0, value: 100), 0)
        XCTAssertEqual(Position.dayPercent(change: 5, value: 5), 0)
        XCTAssertEqual(Position.dayPercent(change: 1, value: 100, explicit: 2.5), 2.5)
        var position = Position(
            symbol: "AAPL",
            name: "Apple",
            quantity: 2,
            lastPrice: 50,
            marketValue: 0,
            dayChangeValue: 4,
            dayChangePercent: 0
        )
        XCTAssertEqual(position.resolvedMarketValue, 100)
        XCTAssertEqual(position.resolvedDayChangePercent, 4.166, accuracy: 0.01)
        position.dayChangePercent = 1.5
        XCTAssertEqual(position.resolvedDayChangePercent, 1.5)
    }

    func testDisplaySymbolForCusipBond() {
        let bond = Position(
            symbol: "03770DAD5",
            name: "APPL 3.25% 2028",
            quantity: 1,
            lastPrice: 98,
            marketValue: 98,
            dayChangeValue: 0,
            dayChangePercent: 0
        )
        XCTAssertEqual(bond.displaySymbol, "APPL 3.25%")
        XCTAssertEqual(bond.displayAccountName, "Account")
        var named = bond
        named.accountName = "Bonds"
        XCTAssertEqual(named.displayAccountName, "Bonds")
        named.accountName = nil
        named.accountId = "abc"
        XCTAssertEqual(named.displayAccountName, "abc")
    }

    func testMoneyFormatAndJSONValue() {
        XCTAssertTrue(MoneyFormat.usd(12.5).contains("12.50"))
        XCTAssertTrue(MoneyFormat.signedUsd(3).contains("+"))
        XCTAssertTrue(MoneyFormat.signedUsd(-3).contains("-") || MoneyFormat.signedUsd(-3).contains("("))
        XCTAssertEqual(MoneyFormat.signedUsd(0).contains("0.00"), true)
        XCTAssertTrue(MoneyFormat.percent(1.5).contains("1.50"))
        XCTAssertEqual(JSONValue.money("$1,234.50"), 1234.50)
        XCTAssertEqual(JSONValue.money("(12.00)"), -12)
        XCTAssertNil(JSONValue.money("AAPL"))
        XCTAssertEqual(JSONValue.number(NSNumber(value: 3)), 3)
        XCTAssertEqual(JSONValue.number("4.5"), 4.5)
        XCTAssertEqual(JSONValue.number(2), 2)
        XCTAssertEqual(JSONValue.number(Optional<Any>.none), 0)
    }

    func testFidelityJSONHelpers() {
        let object: [String: Any] = [
            "Symbol": "VOO",
            "Qty": ["value": "3"],
            "nested": ["person": ["name": "Ada"]]
        ]
        XCTAssertEqual(FidelityJSON.firstString(object, ["symbol"]), "VOO")
        XCTAssertEqual(FidelityJSON.firstNumber(object, ["qty"]), 3)
        XCTAssertEqual(FidelityJSON.string("  "), nil)
        XCTAssertEqual(FidelityJSON.nested(object, ["missing"]).isEmpty, true)
        let person = FidelityJSON.getContextPerson(from: [
            ["getContext": ["person": ["assets": []]]]
        ])
        XCTAssertNotNil(person)
        XCTAssertNil(FidelityJSON.getContextPerson(from: ["skip", ["nope": 1]]))
    }

    func testBrokerAndUpdateCopy() {
        XCTAssertEqual(BrokerKind.fidelity.displayName, "Fidelity")
        XCTAssertEqual(BrokerKind.publicBroker.snapshotFilename, "positions-public.json")
        XCTAssertEqual(AppUpdateStatus.upToDate.message, "You're on the latest version.")
        XCTAssertEqual(AppUpdateStatus.available(latest: "1.0.2").message, "Version 1.0.2 is available.")
        XCTAssertEqual(AppUpdateStatus.failed("x").message, "x")
        XCTAssertTrue(AppUpdateError.invalidArchive.errorDescription?.contains("Broker Widgets") == true)
        XCTAssertTrue(PublicClientError.noAccounts.errorDescription?.contains("Public.com") == true)
        XCTAssertTrue(PublicClientError.http(401, "").errorDescription?.contains("rejected") == true)
        XCTAssertTrue(PublicClientError.http(500, "boom").errorDescription?.contains("500") == true)
    }

    func testPublicAccountNames() {
        XCTAssertEqual(PublicAccountName.display(type: "BROKERAGE", brokerageType: "CASH"), "Brokerage")
        XCTAssertEqual(PublicAccountName.display(type: "BROKERAGE", brokerageType: "MARGIN"), "Brokerage · Margin")
        XCTAssertEqual(PublicAccountName.display(type: "BOND_ACCOUNT", brokerageType: nil), "Bonds")
        XCTAssertEqual(PublicAccountName.display(type: "HIGH_YIELD", brokerageType: nil), "High yield")
        XCTAssertEqual(PublicAccountName.display(type: "TREASURY", brokerageType: nil), "Treasury")
        XCTAssertEqual(PublicAccountName.display(type: "TRADITIONAL_IRA", brokerageType: nil), "Traditional IRA")
        XCTAssertEqual(PublicAccountName.display(type: "ROTH_IRA", brokerageType: nil), "Roth IRA")
        XCTAssertEqual(PublicAccountName.display(type: "ENTITY", brokerageType: nil), "Entity")
        XCTAssertEqual(PublicAccountName.display(type: "RIA_ASSET", brokerageType: nil), "Managed")
        XCTAssertEqual(PublicAccountName.display(type: "CUSTOM_TYPE", brokerageType: nil), "Custom Type")
        XCTAssertEqual(PublicAccountName.display(type: nil, brokerageType: nil), "Account")
    }

    func testDesktopPanelMatchAndSetupSnapshots() {
        XCTAssertEqual(PortfolioSnapshot.setup(.fidelity).status, .needsSignIn)
        XCTAssertEqual(PortfolioSnapshot.setup(.publicBroker).status, .needsSecret)
        XCTAssertEqual(PortfolioSnapshot.placeholder(.fidelity).positions.count, 3)
        XCTAssertTrue(DesktopPanelWindows.matches(titled("Fidelity Positions"), id: "fidelity-desktop"))
        XCTAssertTrue(DesktopPanelWindows.matches(titled("Public Positions"), id: "public-desktop"))
        XCTAssertFalse(DesktopPanelWindows.matches(titled("Other"), id: "fidelity-desktop"))
        XCTAssertFalse(DesktopPanelWindows.matches(titled("Other"), id: "unknown"))
    }

    func testParseChartFallbacks() {
        let meta: [String: Any] = [
            "chart": ["result": [[
                "meta": [
                    "regularMarketChange": NSNumber(value: 1.5),
                    "regularMarketChangePercent": NSNumber(value: 0.7)
                ]
            ]]]
        ]
        let fromMeta = MarketQuotes.parseChart(meta)
        XCTAssertEqual(fromMeta?.change, 1.5)
        XCTAssertEqual(fromMeta?.percent, 0.7)

        let prices: [String: Any] = [
            "chart": ["result": [[
                "meta": [
                    "regularMarketPrice": 110,
                    "previousClose": 100
                ]
            ]]]
        ]
        let fromPrice = MarketQuotes.parseChart(prices)
        XCTAssertEqual(fromPrice?.change, 10)
        XCTAssertEqual(fromPrice?.percent, 10)

        let closes: [String: Any] = [
            "chart": ["result": [[
                "meta": [:],
                "indicators": ["quote": [["close": [NSNull(), 0, 10, 12]]]]
            ]]]
        ]
        let fromCloses = MarketQuotes.parseChart(closes)
        XCTAssertEqual(fromCloses?.change, 2)
        XCTAssertEqual(fromCloses?.percent ?? 0, 20, accuracy: 0.001)
        XCTAssertNil(MarketQuotes.parseChart(["chart": ["result": [[:]]]]))
    }

    func testFillDayChangesSkipsCompleteRows() async {
        let filled = Position(
            symbol: "AAPL",
            name: "Apple",
            quantity: 1,
            lastPrice: 200,
            marketValue: 200,
            dayChangeValue: 1,
            dayChangePercent: 0.5
        )
        let result = await MarketQuotes.fillDayChanges([filled])
        XCTAssertEqual(result[0].dayChangePercent, 0.5)
    }

    func testApplyQuotesFillsMissingMove() {
        let empty = Position(
            symbol: "MSFT",
            name: "Microsoft",
            quantity: 2,
            lastPrice: 400,
            marketValue: 800,
            dayChangeValue: 0,
            dayChangePercent: 0
        )
        let applied = MarketQuotes.applyQuotes([empty], ["MSFT": (change: 3, percent: 0.75)])
        XCTAssertEqual(applied[0].dayChangePercent, 0.75)
        XCTAssertEqual(applied[0].dayChangeValue, 6)
        let fromPercent = MarketQuotes.applyQuotes([empty], ["MSFT": (change: 0, percent: 2)])
        XCTAssertEqual(fromPercent[0].dayChangeValue, 16, accuracy: 0.001)
    }

    private func titled(_ title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.title = title
        return window
    }
}
