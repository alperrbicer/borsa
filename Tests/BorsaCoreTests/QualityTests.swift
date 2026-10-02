import XCTest
@testable import BorsaCore

final class QualityTests: XCTestCase {
    func testRealizedProfitAndCostRemainAccurateAfterPartialAndFullSale() throws {
        var account = DemoAccount()
        let originalTotal = account.totalValue
        let originalProfit = account.totalProfit
        try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 10, limitPrice: 31_250))
        XCTAssertEqual(account.realizedProfit, 24_500)
        XCTAssertEqual(account.totalValue, originalTotal)
        XCTAssertEqual(account.totalProfit, originalProfit)
        try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 30, limitPrice: 31_250))
        XCTAssertEqual(account.realizedProfit, 98_000)
        XCTAssertFalse(account.positions.contains { $0.symbol == "THYAO" })
        XCTAssertEqual(account.totalProfit, originalProfit)
    }

    func testFractionalCostRoundingDoesNotLoseMoney() throws {
        var account = DemoAccount(cash: 0, positions: [.init(symbol: "THYAO", quantity: 3, cost: 100)])
        let initialProfit = account.totalProfit
        for _ in 0..<3 {
            try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 1, limitPrice: 31_250))
            XCTAssertEqual(account.totalProfit, initialProfit)
        }
        XCTAssertEqual(account.realizedProfit, 93_650)
        XCTAssertEqual(account.investedCost, 0)
    }

    func testMixedOrderSequenceConservesValueAndSurvivesReloads() throws {
        var account = DemoAccount()
        let value = account.totalValue, profit = account.totalProfit
        var seed: UInt64 = 42
        func random(_ max: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(max))
        }
        for iteration in 0..<300 {
            let instrument = DemoMarket.instruments[random(DemoMarket.instruments.count)]
            let side: OrderSide = random(2) == 0 ? .buy : .sell
            let price = instrument.price + (random(2) == 0 ? 0 : side == .buy ? -100 : 100)
            let request = OrderRequest(symbol: instrument.symbol, side: side, quantity: random(8) + 1, limitPrice: price)
            let previous = account
            do { try account.submit(request) }
            catch {
                XCTAssertTrue(error as? TradingError == .insufficientShares || error as? TradingError == .insufficientCash)
                XCTAssertEqual(account, previous)
            }
            if iteration % 3 == 0, let pending = account.pendingOrders.first { try account.cancel(pending.id) }
            try account.validateState()
            XCTAssertGreaterThanOrEqual(account.availableCash, 0)
            XCTAssertEqual(account.totalValue, value)
            XCTAssertEqual(account.totalProfit, profit)
            if iteration % 20 == 0 {
                let reloaded = try JSONDecoder().decode(DemoAccount.self, from: JSONEncoder().encode(account))
                XCTAssertEqual(reloaded, account)
                account = reloaded
            }
        }
    }

    func testTurkishSearchMatchesSymbolsNamesAndSectors() {
        for (query, expected) in [("sise", "SISE"), ("şişe", "SISE"), ("TURK HAVA", "THYAO"), (" tupras ", "TUPRS"), ("BİM", "BIMAS"), ("savunma", "ASELS")] {
            XCTAssertEqual(MarketQuery.find(DemoMarket.instruments, query: query, sort: .symbol).first?.symbol, expected, query)
        }
        XCTAssertEqual(MarketQuery.find(DemoMarket.instruments, query: "bankacilik", sort: .symbol).count, 2)
        XCTAssertTrue(MarketQuery.find(DemoMarket.instruments, query: "yok", sort: .symbol).isEmpty)
    }

    func testMarketSortIsDeterministicForEqualChanges() {
        let first = Instrument(symbol: "AAA", name: "A", sector: "", price: 100, previousClose: 100)
        let second = Instrument(symbol: "BBB", name: "B", sector: "", price: 100, previousClose: 100)
        for sort in MarketSort.allCases {
            XCTAssertEqual(MarketQuery.find([second, first], query: "", sort: sort).map(\.symbol), ["AAA", "BBB"])
        }
        let descending = MarketQuery.find(DemoMarket.instruments, query: "", sort: .gainers)
        XCTAssertEqual(descending.first?.symbol, "ASELS")
        XCTAssertEqual(descending.last?.symbol, "SISE")
    }
}
