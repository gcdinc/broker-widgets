import XCTest
@testable import BrokerWidgets

final class FidelityHoldingRulesTests: XCTestCase {
    func testAcceptsRealHoldings() {
        XCTAssertTrue(FidelityHoldingRules.isPlausibleHolding(holding("AAPL", qty: 0.95, last: 229, value: 217.55)))
        XCTAssertTrue(FidelityHoldingRules.isPlausibleHolding(holding("SPAXX", qty: 12.4, last: 1, value: 12.4)))
        XCTAssertTrue(FidelityHoldingRules.isPlausibleHolding(holding("FXAIX", qty: 10, last: 200, value: 2000)))
        XCTAssertTrue(FidelityHoldingRules.isPlausibleHolding(holding("CT529", qty: 1, last: 4884.96, value: 4884.96)))
    }

    func testRejectsChromeWords() {
        for symbol in ["HIGH", "LOW", "DISMISS", "SETTINGS", "POSITIONS", "INDIVIDU", "QTY", "A"] {
            XCTAssertFalse(FidelityHoldingRules.isTicker(symbol), symbol)
            XCTAssertFalse(
                FidelityHoldingRules.isPlausibleHolding(holding(symbol, qty: 5, last: 10, value: 50)),
                symbol
            )
        }
    }

    func testRejectsAccountNumbersAsTickers() {
        XCTAssertFalse(FidelityHoldingRules.isTicker("Z26169565"))
        XCTAssertFalse(FidelityHoldingRules.isTicker("244483495"))
    }

    func testRejectsYearUsedAsLastPrice() {
        XCTAssertFalse(FidelityHoldingRules.isPlausibleHolding(holding("AAPL", qty: 5, last: 2026, value: 9)))
    }

    func testRejectsMismatchedQuantityAndValue() {
        XCTAssertFalse(FidelityHoldingRules.isPlausibleHolding(holding("SCHD", qty: 34.8, last: 0.28, value: 95.51)))
    }

    func testRejectsQuantityCopiedFromAccountDigits() {
        XCTAssertFalse(FidelityHoldingRules.isPlausibleHolding(holding("CT2042459", qty: 2_042_459, last: 20, value: 40_849_180)))
    }

    func testMergesDuplicateSymbolQuantity() {
        let loose = holding("AAPL", qty: 1, last: 200, value: 200)
        var withAccount = holding("AAPL", qty: 1, last: 200, value: 200)
        withAccount.accountId = "Z26169565"
        withAccount.dayChangeValue = 1.5
        let merged = FidelityHoldingRules.mergeDuplicates([loose, withAccount])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].accountId, "Z26169565")
        XCTAssertEqual(merged[0].dayChangeValue, 1.5)
    }

    func testKeepsSameSymbolInTwoAccounts() {
        var a = holding("SPAXX", qty: 1, last: 1, value: 1)
        a.accountId = "Z1"
        var b = holding("SPAXX", qty: 1, last: 1, value: 1)
        b.accountId = "Z2"
        XCTAssertEqual(FidelityHoldingRules.mergeDuplicates([a, b]).count, 2)
    }

    func testVersionCompare() {
        XCTAssertEqual(AppSoftwareVersion.compareDotted("1.0.1", "1.0.0"), 1)
        XCTAssertEqual(AppSoftwareVersion.compareDotted("1.0.0", "1.0.1"), -1)
        XCTAssertEqual(AppSoftwareVersion.compareDotted("1.0", "1.0.0"), 0)
        let older = AppSoftwareVersion(marketing: "1.0.0", build: "1", zipURL: AppConstants.latestZipURL)
        let newer = AppSoftwareVersion(marketing: "1.0.1", build: "2", zipURL: AppConstants.latestZipURL)
        XCTAssertTrue(AppSoftwareVersion.isNewer(newer, than: older))
        XCTAssertFalse(AppSoftwareVersion.isNewer(older, than: newer))
        XCTAssertTrue(
            AppSoftwareVersion.isNewer(
                AppSoftwareVersion(marketing: "1.0.1", build: "3", zipURL: AppConstants.latestZipURL),
                than: AppSoftwareVersion(marketing: "1.0.1", build: "2", zipURL: AppConstants.latestZipURL)
            )
        )
    }

    func testPricesAgreeRejectsYearAndHugeValue() {
        XCTAssertFalse(FidelityHoldingRules.pricesAgree(last: 2024, quantity: 1, value: 2024))
        XCTAssertFalse(FidelityHoldingRules.pricesAgree(last: 10, quantity: 1, value: 25_000_001))
        XCTAssertFalse(FidelityHoldingRules.pricesAgree(last: 10, quantity: 1, value: 2_612_459))
        XCTAssertTrue(FidelityHoldingRules.pricesAgree(last: 0, quantity: 1, value: 50))
        XCTAssertFalse(FidelityHoldingRules.isSaneQuantity(0))
        XCTAssertFalse(FidelityHoldingRules.isSaneQuantity(10_000_000))
        XCTAssertTrue(FidelityHoldingRules.isSaneQuantity(0.01))
    }

    func testPicksRicherDuplicate() {
        var thin = holding("VOO", qty: 2, last: 500, value: 1_000)
        thin.name = "VOO"
        var rich = holding("VOO", qty: 2, last: 500, value: 1_000)
        rich.name = "Vanguard S&P 500"
        rich.accountId = "Z26169565"
        rich.dayChangeValue = 12
        let merged = FidelityHoldingRules.mergeDuplicates([thin, rich])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Vanguard S&P 500")
        XCTAssertEqual(merged[0].dayChangeValue, 12)
    }

    private func holding(_ symbol: String, qty: Double, last: Double, value: Double) -> Position {
        Position(
            symbol: symbol,
            name: symbol,
            quantity: qty,
            lastPrice: last,
            marketValue: value,
            dayChangeValue: 0,
            dayChangePercent: 0
        )
    }
}
