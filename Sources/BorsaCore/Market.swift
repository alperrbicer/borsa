import Foundation

public struct Instrument: Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let sector: String
    public let price: Int64
    public let previousClose: Int64
    public var changePercent: Double { Double(price - previousClose) / Double(previousClose) * 100 }

    public init(symbol: String, name: String, sector: String, price: Int64, previousClose: Int64) {
        self.symbol = symbol
        self.name = name
        self.sector = sector
        self.price = price
        self.previousClose = previousClose
    }
}

/// Fixed, invented quotes for interface development. These are not market data.
public enum DemoMarket {
    public static let instruments: [Instrument] = [
        .init(symbol: "THYAO", name: "Türk Hava Yolları", sector: "Ulaştırma", price: 31250, previousClose: 30600),
        .init(symbol: "ASELS", name: "Aselsan", sector: "Savunma", price: 6840, previousClose: 6670),
        .init(symbol: "TUPRS", name: "Tüpraş", sector: "Enerji", price: 16820, previousClose: 17040),
        .init(symbol: "GARAN", name: "Garanti BBVA", sector: "Bankacılık", price: 12460, previousClose: 12280),
        .init(symbol: "SISE", name: "Şişecam", sector: "Sanayi", price: 4532, previousClose: 4598),
        .init(symbol: "KCHOL", name: "Koç Holding", sector: "Holding", price: 18740, previousClose: 18520),
        .init(symbol: "BIMAS", name: "BİM Mağazalar", sector: "Perakende", price: 52400, previousClose: 51600),
        .init(symbol: "AKBNK", name: "Akbank", sector: "Bankacılık", price: 6275, previousClose: 6340)
    ]

    public static func instrument(_ symbol: String) -> Instrument? {
        instruments.first { $0.symbol == symbol }
    }

    /// Synthetic line ending at the displayed quote; no historical-data claim.
    public static func history(for instrument: Instrument, days: Int = 1) -> [Double] {
        let end = Double(instrument.price) / 100
        let start = Double(instrument.previousClose) / 100 * (1 - Double(days - 1) * 0.0007)
        let seed = Double(instrument.symbol.utf8.reduce(0) { $0 + Int($1) })
        return (0..<40).map { index in
            let progress = Double(index) / 39
            let wave = sin(progress * 25 + seed) * sin(progress * .pi) * end * 0.008
            return start + (end - start) * progress + wave
        }
    }
}

public enum Money {
    public static func formatted(_ cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        return formatter.string(from: NSDecimalNumber(value: cents).dividing(by: 100)) ?? "—"
    }

    /// Accepts a plain Turkish decimal amount, without ambiguous grouping separators.
    public static func parse(_ text: String) -> Int64? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(raw.contains(".") && raw.contains(",")) else { return nil }
        let value = raw.replacingOccurrences(of: ".", with: ",")
        let pieces = value.split(separator: ",", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let integer = pieces.first, !integer.isEmpty,
              integer.allSatisfy({ $0.isASCII && $0.isNumber }), integer.count <= 9,
              let whole = Int64(integer) else { return nil }
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= 2, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let cents = Int64(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        return whole * 100 + cents
    }

    public static func editable(_ cents: Int64) -> String {
        "\(cents / 100),\(String(format: "%02lld", cents % 100))"
    }
}
