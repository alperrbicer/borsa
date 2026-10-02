import XCTest
@testable import BorsaCore

final class PaperModelTests: XCTestCase {
    func testPriceInputPreservesFourDecimalPlaces() {
        XCTAssertEqual(PaperFormat.parsePrice("123,4567"), 1_234_567)
        XCTAssertEqual(PaperFormat.parsePrice("0.0001"), 1)
        for text in ["1.234,56", "NaN", "-1", "0", "100001", "1.00001", "1e4"] {
            XCTAssertNil(PaperFormat.parsePrice(text), text)
        }
    }
    func testUnavailableMoneyHasNoSyntheticFallback() {
        XCTAssertEqual(PaperFormat.money(nil,"USD"), "—")
        XCTAssertEqual(PaperFormat.price(nil,"TRY"), "—")
    }
    func testQuoteFreshnessRejectsOldAndFutureData() throws {
        let now = Date().timeIntervalSince1970 * 1000
        func quote(at: Double) throws -> PaperQuote {
            let data = try JSONSerialization.data(withJSONObject:["priceUnits":1000000,"timestamp":at,"receivedAt":at,"source":"Test fixture","quality":"realtime","delaySeconds":0,"sessionOpen":true])
            return try JSONDecoder().decode(PaperQuote.self,from:data)
        }
        XCTAssertTrue(try quote(at:now).fresh)
        XCTAssertFalse(try quote(at:now-60000).fresh)
        XCTAssertFalse(try quote(at:now+60000).fresh)
    }
}
