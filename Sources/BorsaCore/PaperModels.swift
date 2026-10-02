import Foundation

struct PaperSnapshot: Codable, Sendable {
    let version: Int
    let serverTime: Double
    let revision: Int
    let createdAt: Double
    let instruments: [PaperInstrument]
    let wallets: [PaperWallet]
    let positions: [PaperPosition]
    let orders: [PaperOrder]
    let news: [PaperNews]
    let decisions: [PaperDecision]
    let settings: PaperSettings
    let health: [ProviderHealth]
    let lastCycleAt: Double?
    let watchlist: [String]
    var reviews: [PaperDecision] { decisions.filter { $0.state == "review" && $0.expiresAt > Date().timeIntervalSince1970 * 1000 } }
}
struct PaperInstrument: Codable, Identifiable, Hashable, Sendable {
    var id: String { symbol }
    let symbol: String, name: String, sector: String, market: String, currency: String
    let quote: PaperQuote?
    let history: [PaperPoint]
    let blockedReason: String?
}
struct PaperQuote: Codable, Hashable, Sendable {
    let priceUnits: Int64
    let bidUnits: Int64?, askUnits: Int64?
    let timestamp: Double, receivedAt: Double
    let source: String, quality: String
    let delaySeconds: Int
    let sessionOpen: Bool
    let previousCloseUnits: Int64?
    var fresh: Bool {
        let now = Date().timeIntervalSince1970 * 1000
        return timestamp <= now + 2000 && receivedAt <= now + 2000 && now - timestamp < 45_000 && now - receivedAt < 45_000
    }
}
struct PaperPoint: Codable, Identifiable, Hashable, Sendable {
    var id: Double { at }
    let at: Double
    let priceUnits: Int64
}
struct PaperWallet: Codable, Identifiable, Sendable {
    var id: String { currency }
    let currency: String
    let initialCashCents: Int64, cashCents: Int64, availableCents: Int64, reservedCents: Int64
    let feesCents: Int64, realizedCents: Int64
    let holdingValueCents: Int64?, netProfitCents: Int64?
    let dailyLossPercent: Double?, drawdownPercent: Double?
    var totalCents: Int64? { holdingValueCents.map { cashCents + $0 } }
}
struct PaperPosition: Codable, Identifiable, Sendable {
    var id: String { symbol }
    let symbol: String, currency: String
    let quantity: Int
    let costCents: Int64, marketValueCents: Int64?, profitCents: Int64?
}
struct PaperOrder: Codable, Identifiable, Sendable {
    let id: String, symbol: String, side: String, status: String, reason: String, source: String
    let quantity: Int, remaining: Int, filledQty: Int
    let limitUnits: Int64, grossUnits: Int64, feesCents: Int64
    let createdAt: Double, expiresAt: Double, filledAt: Double?
    let executionUnits: Int64?
    let decisionId: String?
    var statusTitle: String {
        switch status { case "filled": "Gerçekleşti"; case "pending": filledQty > 0 ? "Kısmen gerçekleşti" : "Bekliyor"; case "cancelled": "İptal"; default: "Süresi doldu" }
    }
}
struct PaperNews: Codable, Identifiable, Sendable {
    let id: String, title: String, summary: String, source: String, url: String
    let symbols: [String]
    let publishedAt: Double, receivedAt: Double
    let delaySeconds: Int
}
struct PaperDecision: Codable, Identifiable, Sendable {
    let id: String, newsId: String, symbol: String, action: String, state: String
    let reason: String, companyImpact: String, sectorImpact: String, portfolioImpact: String
    let sourceURL: String, source: String, confidence: String, analysisVersion: String
    let createdAt: Double, expiresAt: Double
    let proposedSide: String?, orderId: String?
    var stateTitle: String {
        switch state { case "review": "İnceleme bekliyor"; case "queued": "Emir bekliyor"; case "executed": "Gerçekleşti"; case "rejected": "Reddedildi"; case "expired": "Yanıt gelmedi"; case "closed": "Emir kapandı"; default: "İşlem yapılmadı" }
    }
}
struct PaperSettings: Codable, Sendable {
    let mode: String
    let maxPositionPercent: Int, maxSectorPercent: Int, maxDailyLossPercent: Int
    let commissionBps: Int, slippageBps: Int, maxDailyOrders: Int, cooldownMinutes: Int
    var modeTitle: String { switch mode { case "auto": "Otomatik"; case "paused": "Duraklatıldı"; default: "İnceleme" } }
}
struct PaperPreview: Codable, Identifiable, Sendable {
    let id: String, symbol: String, side: String, currency: String
    let quantity: Int
    let limitUnits: Int64, grossCents: Int64, feeCents: Int64
    let expiresAt: Double
    var confirmation: [String: Any] { ["symbol":symbol,"side":side,"quantity":quantity,"limitUnits":limitUnits,"feeCents":feeCents,"expiresAt":expiresAt] }
}
struct ProviderHealth: Codable, Identifiable, Sendable {
    let id: String, name: String, status: String, message: String
    let lastSuccessAt: Double?
}
enum PaperFormat {
    static func money(_ cents: Int64?, _ currency: String) -> String {
        guard let cents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: currency).locale(Locale(identifier: "tr_TR")))
    }
    static func price(_ units: Int64?, _ currency: String) -> String {
        guard let units else { return "—" }
        return (Double(units) / 10000).formatted(.currency(code: currency).locale(Locale(identifier: "tr_TR")).precision(.fractionLength(2...4)))
    }
    static func date(_ ms: Double?) -> String {
        guard let ms else { return "Henüz yok" }
        return Date(timeIntervalSince1970: ms / 1000).formatted(.dateTime.day().month().hour().minute().second().locale(Locale(identifier: "tr_TR")))
    }
    static func parsePrice(_ value: String) -> Int64? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard clean.range(of: #"^\d{1,6}(\.\d{1,4})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let units = NSDecimalNumber(decimal: decimal * 10000).int64Value
        return units > 0 && units <= 1_000_000_000 ? units : nil
    }
}
