import XCTest
@testable import BorsaCore

final class TradingTests: XCTestCase {
    func testBuyUpdatesCashAndWeightedCostExactly() throws {
        var account = DemoAccount()
        let originalTotal = account.totalValue
        let order = try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 10, limitPrice: 32_000))
        XCTAssertEqual(order.status, .filled)
        XCTAssertEqual(order.executionPrice, 31_250)
        XCTAssertEqual(account.cash, 9_687_500)
        XCTAssertEqual(account.positions.first { $0.symbol == "THYAO" }?.quantity, 50)
        XCTAssertEqual(account.positions.first { $0.symbol == "THYAO" }?.cost, 1_464_500)
        XCTAssertEqual(account.totalValue, originalTotal)
    }

    func testPendingBuyReservesLimitAndCancelReleasesIt() throws {
        var account = DemoAccount()
        let order = try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 10, limitPrice: 30_000))
        XCTAssertEqual(order.status, .pending)
        XCTAssertEqual(account.cash, 10_000_000)
        XCTAssertEqual(account.reservedCash, 300_000)
        XCTAssertEqual(account.availableCash, 9_700_000)
        try account.cancel(order.id)
        XCTAssertEqual(account.availableCash, 10_000_000)
        XCTAssertEqual(account.orders[0].status, .cancelled)
    }

    func testCannotOverspendReservedCash() throws {
        var account = DemoAccount(cash: 60_000, positions: [])
        try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 30_000))
        let before = account
        XCTAssertThrowsError(try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 31_250))) {
            XCTAssertEqual($0 as? TradingError, .insufficientCash)
        }
        XCTAssertEqual(account, before)
    }

    func testSaleRemovesPositionAndCreditsCash() throws {
        var account = DemoAccount()
        let total = account.totalValue
        try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 40, limitPrice: 31_000))
        XCTAssertNil(account.positions.first { $0.symbol == "THYAO" })
        XCTAssertEqual(account.cash, 11_250_000)
        XCTAssertEqual(account.totalValue, total)
    }

    func testPartialSalePreservesProportionalCost() throws {
        var account = DemoAccount()
        try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 10, limitPrice: 31_250))
        let holding = try XCTUnwrap(account.positions.first { $0.symbol == "THYAO" })
        XCTAssertEqual(holding.quantity, 30)
        XCTAssertEqual(holding.cost, 864_000)
    }

    func testPendingSaleReservesSharesAndCancelReleasesThem() throws {
        var account = DemoAccount()
        let order = try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 30, limitPrice: 35_000))
        XCTAssertEqual(order.status, .pending)
        XCTAssertEqual(account.availableShares("THYAO"), 10)
        XCTAssertThrowsError(try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 11, limitPrice: 31_250))) {
            XCTAssertEqual($0 as? TradingError, .insufficientShares)
        }
        try account.cancel(order.id)
        XCTAssertEqual(account.availableShares("THYAO"), 40)
    }

    func testDuplicateSubmissionIsIdempotentEvenAfterPersistence() throws {
        var account = DemoAccount()
        let request = OrderRequest(symbol: "THYAO", side: .buy, quantity: 10, limitPrice: 31_250)
        let first = try account.submit(request)
        let encoded = try JSONEncoder().encode(account)
        account = try JSONDecoder().decode(DemoAccount.self, from: encoded)
        let second = try account.submit(request)
        XCTAssertEqual(first, second)
        XCTAssertEqual(account.orders.count, 1)
        XCTAssertEqual(account.cash, 9_687_500)
    }

    func testConflictingDuplicateIsRejected() throws {
        var account = DemoAccount()
        let id = UUID()
        try account.submit(.init(id: id, symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 31_250))
        XCTAssertThrowsError(try account.submit(.init(id: id, symbol: "THYAO", side: .buy, quantity: 2, limitPrice: 31_250))) {
            XCTAssertEqual($0 as? TradingError, .duplicateConflict)
        }
    }

    func testInvalidInputsLeaveAccountUnchanged() {
        let invalid: [OrderRequest] = [
            .init(symbol: "THYAO", side: .buy, quantity: 0, limitPrice: 31_250),
            .init(symbol: "THYAO", side: .buy, quantity: -1, limitPrice: 31_250),
            .init(symbol: "THYAO", side: .buy, quantity: Int.max, limitPrice: Int64.max),
            .init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 0),
            .init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: -1),
            .init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: Int64.max),
            .init(symbol: "UNKNOWN", side: .buy, quantity: 1, limitPrice: 1),
            .init(symbol: "THYAO", side: .sell, quantity: 41, limitPrice: 31_250)
        ]
        for request in invalid {
            var account = DemoAccount()
            let before = account
            XCTAssertThrowsError(try account.submit(request))
            XCTAssertEqual(account, before)
        }
    }

    func testCannotCancelAFilledOrder() throws {
        var account = DemoAccount()
        let order = try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 31_250))
        XCTAssertThrowsError(try account.cancel(order.id)) { XCTAssertEqual($0 as? TradingError, .cannotCancel) }
    }

    func testUnknownCancellationIsRejected() {
        var account = DemoAccount()
        XCTAssertThrowsError(try account.cancel(UUID()))
    }

    func testPersistencePreservesReservationsAndPositions() throws {
        var account = DemoAccount()
        try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 10, limitPrice: 30_000))
        try account.submit(.init(symbol: "ASELS", side: .sell, quantity: 20, limitPrice: 8_000))
        let restored = try JSONDecoder().decode(DemoAccount.self, from: JSONEncoder().encode(account))
        XCTAssertEqual(restored, account)
        XCTAssertEqual(restored.availableCash, 9_700_000)
        XCTAssertEqual(restored.availableShares("ASELS"), 80)
    }

    func testTurkishPriceParserPreservesCentsAndRejectsAmbiguity() {
        XCTAssertEqual(Money.parse("312,50"), 31_250)
        XCTAssertEqual(Money.parse("312.50"), 31_250)
        XCTAssertEqual(Money.parse("12.5"), 1_250)
        XCTAssertEqual(Money.parse("0,01"), 1)
        XCTAssertEqual(Money.parse(" 12,5 "), 1_250)
        XCTAssertEqual(Money.parse("12"), 1_200)
        for input in ["1.000,00", "1,000.00", "1.000", "12..5", "12,345", "1e9", "-12", "", ",2", "nan", "9999999999999999", "₺20"] {
            XCTAssertNil(Money.parse(input), input)
        }
    }

    func testEditablePricesRoundTrip() {
        for value: Int64 in [0, 1, 99, 100, 31_250, 100_000_000] {
            XCTAssertEqual(Money.parse(Money.editable(value)), value)
        }
    }

    func testSyntheticChartEndsAtDisplayedPrice() {
        for instrument in DemoMarket.instruments {
            for days in [1, 7, 30, 90] {
                XCTAssertEqual(DemoMarket.history(for: instrument, days: days).last!, Double(instrument.price) / 100, accuracy: 0.001)
            }
        }
    }

    func testUnconfiguredBrokerAlwaysRejectsRealOrders() async {
        do {
            _ = try await UnconfiguredBroker().submit(.init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 31_250), confirmationToken: "demo")
            XCTFail("An unconfigured broker must not accept real orders")
        } catch { XCTAssertEqual(error as? TradingError, .liveUnavailable) }
    }
}
