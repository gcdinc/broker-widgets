import XCTest
@testable import BrokerWidgets

final class FidelityCaptureParserTests: XCTestCase {
    func testNeedsSignInOnLoginPage() {
        let snapshot = FidelityCaptureParser.snapshot(from: CapturedPage(
            href: "https://digital.fidelity.com/prgw/digital/login/full-page",
            title: "Log In",
            hasPassword: true,
            captured: [],
            text: nil
        ))
        XCTAssertEqual(snapshot.status, .needsSignIn)
        XCTAssertTrue(snapshot.positions.isEmpty)
    }

    func testEmptyWhenSignedInWithoutRows() {
        let snapshot = FidelityCaptureParser.snapshot(from: CapturedPage(
            href: "https://digital.fidelity.com/ftgw/digital/portfolio/positions",
            title: "Positions",
            hasPassword: false,
            captured: [],
            text: nil
        ))
        XCTAssertEqual(snapshot.status, .empty)
    }

    func testCollectsKnownPositionRows() throws {
        let json = """
        {"positionDetails":[{"symbol":"AAPL","quantity":0.95,"lastPrice":229,"marketValue":217.55,"todaysGainLoss":1.2}]}
        """
        let snapshot = FidelityCaptureParser.snapshot(from: page(json: json))
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.positions.map(\.symbol), ["AAPL"])
        XCTAssertEqual(snapshot.positions[0].quantity, 0.95, accuracy: 0.001)
    }

    func testIgnoresAccountTotalsAndChrome() throws {
        let json = """
        {"positions":[
          {"symbol":"INDIVIDU","quantity":1,"lastPrice":32700,"marketValue":32700},
          {"symbol":"HIGH","quantity":5,"lastPrice":10,"marketValue":50},
          {"symbol":"Z26169565","quantity":1,"lastPrice":100,"marketValue":100}
        ]}
        """
        let snapshot = FidelityCaptureParser.snapshot(from: page(json: json))
        XCTAssertTrue(snapshot.positions.isEmpty)
        XCTAssertEqual(snapshot.status, .empty)
    }

    func testWorkplace529WhenMissingFromGrid() {
        let json = """
        {"getContext":{"person":{"assets":[{
          "acctNum":"603376654",
          "acctType":"Brokerage",
          "acctSubtype":"529",
          "preferenceDetail":{"name":"Individual-529"},
          "gainLossBalanceDetail":{"totalMarketVal":4884.96,"todaysGainLoss":12,"todaysGainLossPct":0.25}
        }]}}}
        """
        let snapshot = FidelityCaptureParser.snapshot(from: page(json: json))
        XCTAssertEqual(snapshot.positions.map(\.symbol), ["CT529"])
        XCTAssertEqual(snapshot.positions[0].accountId, "603376654")
        XCTAssertEqual(snapshot.positions[0].marketValue, 4884.96, accuracy: 0.01)
    }

    func testSkipsExternalAndDuplicateWorkplace() {
        let json = """
        {"getContext":{"person":{"assets":[
          {"acctNum":"EXT1","acctType":"External","acctSubtype":"HYS","preferenceDetail":{"name":"External HYS"},
           "gainLossBalanceDetail":{"totalMarketVal":51000}},
          {"acctNum":"Z1","acctType":"Brokerage","acctSubtype":"INDIVIDUAL","preferenceDetail":{"name":"Individual"},
           "gainLossBalanceDetail":{"totalMarketVal":32000}}
        ]}},
        "positionDetails":[{"symbol":"AAPL","quantity":1,"lastPrice":200,"marketValue":200,"acctNum":"Z1"}]}
        """
        let snapshot = FidelityCaptureParser.snapshot(from: page(json: json))
        XCTAssertEqual(snapshot.positions.map(\.symbol), ["AAPL"])
        XCTAssertFalse(snapshot.positions.contains { $0.symbol == "CT529" })
    }

    func testParsesVisibleTextRows() {
        let snapshot = FidelityCaptureParser.snapshot(from: CapturedPage(
            href: "https://digital.fidelity.com/ftgw/digital/portfolio/positions",
            title: "Positions",
            hasPassword: false,
            captured: [],
            text: "AAPL\n2\n200.00\n400.00\nHIGH\n5\n10\n50"
        ))
        XCTAssertEqual(snapshot.positions.map(\.symbol), ["AAPL"])
        XCTAssertEqual(snapshot.positions[0].marketValue, 400, accuracy: 0.01)
    }

    func testInlineVisibleTextAndContextTotal() {
        let context = """
        {"getContext":{"person":{"balances":{"balanceDetail":{"gainLossBalanceDetail":{
          "fidelityTotalMktVal":37500,"todaysGainLoss":40,"todaysGainLossPct":0.1
        }}}}}}
        """
        let snapshot = FidelityCaptureParser.snapshot(from: CapturedPage(
            href: "https://digital.fidelity.com/ftgw/digital/portfolio/positions",
            title: "Positions",
            hasPassword: false,
            captured: [CapturedNetwork(url: "ctx", text: context)],
            text: "SPAXX 12.4 1.00 12.40"
        ))
        XCTAssertEqual(snapshot.positions.map(\.symbol), ["SPAXX"])
        XCTAssertEqual(snapshot.totalValue, 37500, accuracy: 0.01)
        XCTAssertEqual(snapshot.dayChangeValue, 40, accuracy: 0.01)
    }

    private func page(json: String) -> CapturedPage {
        CapturedPage(
            href: "https://digital.fidelity.com/ftgw/digital/portfolio/positions",
            title: "Positions",
            hasPassword: false,
            captured: [CapturedNetwork(url: "positions", text: json)],
            text: nil
        )
    }
}
