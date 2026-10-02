import Foundation

public enum OrderSide: String, Codable, CaseIterable, Sendable {
    case buy, sell
    public var title: String { self == .buy ? "Alış" : "Satış" }
}

public enum OrderStatus: String, Codable, Sendable {
    case filled, pending, cancelled
    public var title: String {
        switch self {
        case .filled: "Gerçekleşti"
        case .pending: "Bekliyor"
        case .cancelled: "İptal edildi"
        }
    }
}

public struct Position: Codable, Equatable, Identifiable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public var quantity: Int
    public var cost: Int64
    public var averageCost: Int64 { quantity > 0 ? cost / Int64(quantity) : 0 }

    public init(symbol: String, quantity: Int, cost: Int64) {
        self.symbol = symbol
        self.quantity = quantity
        self.cost = cost
    }
}

public struct OrderRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let symbol: String
    public let side: OrderSide
    public let quantity: Int
    public let limitPrice: Int64

    public init(id: UUID = UUID(), symbol: String, side: OrderSide, quantity: Int, limitPrice: Int64) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.limitPrice = limitPrice
    }
}

public struct Order: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { request.id }
    public let request: OrderRequest
    public let createdAt: Date
    public var status: OrderStatus
    public let executionPrice: Int64?
}

public enum TradingError: Error, LocalizedError, Equatable {
    case invalidQuantity, invalidPrice, unknownInstrument, insufficientCash, insufficientShares
    case cannotCancel, duplicateConflict, liveUnavailable, invalidState, accountLimit

    public var errorDescription: String? {
        switch self {
        case .invalidQuantity: "Adet, 1 ile 100.000 arasında bir tam sayı olmalı."
        case .invalidPrice: "Fiyatı 0,01 ile 1.000.000,00 TL arasında gir."
        case .unknownInstrument: "Hisse bulunamadı."
        case .insufficientCash: "Bu emir için kullanılabilir bakiyen yetersiz."
        case .insufficientShares: "Bu emir için satılabilir hisse adedin yetersiz."
        case .cannotCancel: "Yalnızca bekleyen emirler iptal edilebilir."
        case .duplicateConflict: "Bu emir kimliği farklı bir işlem için kullanılmış."
        case .liveUnavailable: "Gerçek alım satım için aracı kurum bağlantısı henüz kurulmadı."
        case .invalidState: "Hesap kaydında tutarsızlık bulundu. Kayıt korunuyor; geçerli bir yedek geri yükle."
        case .accountLimit: "Bu işlem hesabın kayıt veya tutar sınırını aşıyor."
        }
    }
}

/// A deliberately local simulator. It never sends an order over the network.
/// Integer kuruş arithmetic keeps balances exact. Pending orders reserve cash/shares.
public struct DemoAccount: Codable, Equatable, Sendable {
    public private(set) var cash: Int64
    public private(set) var positions: [Position]
    public private(set) var orders: [Order] = []
    public private(set) var realizedProfit: Int64 = 0
    public static let maximumMoney: Int64 = 1_000_000_000_000_000
    public static let maximumOrders = 10_000

    private enum CodingKeys: String, CodingKey { case cash, positions, orders, realizedProfit }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cash = try container.decode(Int64.self, forKey: .cash)
        positions = try container.decode([Position].self, forKey: .positions)
        orders = try container.decode([Order].self, forKey: .orders)
        realizedProfit = try container.decodeIfPresent(Int64.self, forKey: .realizedProfit) ?? 0
        try validateState()
        // Version 1 only had the fixed starting cash/holdings and buy/sell operations.
        // cash + remaining cost - starting cash - starting cost recovers realized P/L.
        if !container.contains(.realizedProfit) {
            realizedProfit = cash + positions.reduce(0) { $0 + $1.cost } - 12_214_500
            try validateState()
        }
    }

    public init(cash: Int64 = 10_000_000, positions: [Position] = [
        .init(symbol: "THYAO", quantity: 40, cost: 1_152_000),
        .init(symbol: "ASELS", quantity: 100, cost: 630_000),
        .init(symbol: "TUPRS", quantity: 25, cost: 432_500)
    ]) {
        self.cash = cash
        self.positions = positions
    }

    public var reservedCash: Int64 {
        orders.filter { $0.status == .pending && $0.request.side == .buy }
            .reduce(0) { $0 + $1.request.limitPrice * Int64($1.request.quantity) }
    }

    public var availableCash: Int64 { cash - reservedCash }

    public func availableShares(_ symbol: String) -> Int {
        let owned = positions.first { $0.symbol == symbol }?.quantity ?? 0
        let reserved = orders.filter {
            $0.status == .pending && $0.request.side == .sell && $0.request.symbol == symbol
        }.reduce(0) { $0 + $1.request.quantity }
        return owned - reserved
    }

    public var holdingsValue: Int64 {
        positions.reduce(0) { $0 + (DemoMarket.instrument($1.symbol)?.price ?? 0) * Int64($1.quantity) }
    }

    public var totalValue: Int64 { cash + holdingsValue }
    public var unrealizedProfit: Int64 { holdingsValue - positions.reduce(0) { $0 + $1.cost } }
    public var totalProfit: Int64 { unrealizedProfit + realizedProfit }
    public var investedCost: Int64 { positions.reduce(0) { $0 + $1.cost } }
    public var pendingOrders: [Order] { orders.filter { $0.status == .pending } }

    public func validateState() throws {
        guard (0...Self.maximumMoney).contains(cash),
              (-Self.maximumMoney...Self.maximumMoney).contains(realizedProfit),
              positions.count <= DemoMarket.instruments.count, orders.count <= Self.maximumOrders,
              Set(positions.map(\.symbol)).count == positions.count,
              Set(orders.map(\.id)).count == orders.count else { throw TradingError.invalidState }
        for position in positions {
            guard DemoMarket.instrument(position.symbol) != nil, (1...1_000_000).contains(position.quantity),
                  (0...Self.maximumMoney).contains(position.cost) else { throw TradingError.invalidState }
        }
        for order in orders {
            let request = order.request
            guard DemoMarket.instrument(request.symbol) != nil, (1...100_000).contains(request.quantity),
                  (1...100_000_000).contains(request.limitPrice), order.createdAt.timeIntervalSince1970.isFinite else {
                throw TradingError.invalidState
            }
            if order.status == .filled {
                guard let price = order.executionPrice, (1...100_000_000).contains(price),
                      request.side == .buy ? price <= request.limitPrice : price >= request.limitPrice else {
                    throw TradingError.invalidState
                }
            } else if order.executionPrice != nil { throw TradingError.invalidState }
        }
        guard reservedCash <= cash else { throw TradingError.invalidState }
        for instrument in DemoMarket.instruments {
            guard availableShares(instrument.symbol) >= 0 else { throw TradingError.invalidState }
        }
    }

    public func validate(_ request: OrderRequest) throws {
        try validateState()
        guard orders.count < Self.maximumOrders else { throw TradingError.accountLimit }
        guard (1...100_000).contains(request.quantity) else { throw TradingError.invalidQuantity }
        guard (1...100_000_000).contains(request.limitPrice) else { throw TradingError.invalidPrice }
        guard DemoMarket.instrument(request.symbol) != nil else { throw TradingError.unknownInstrument }
        if request.side == .buy {
            let quantity = positions.first { $0.symbol == request.symbol }?.quantity ?? 0
            guard quantity + request.quantity <= 1_000_000 else { throw TradingError.accountLimit }
            guard request.limitPrice * Int64(request.quantity) <= availableCash else { throw TradingError.insufficientCash }
        } else {
            guard request.quantity <= availableShares(request.symbol) else { throw TradingError.insufficientShares }
        }
    }

    @discardableResult
    public mutating func submit(_ request: OrderRequest, now: Date = Date()) throws -> Order {
        try validateState()
        if let existing = orders.first(where: { $0.id == request.id }) {
            guard existing.request == request else { throw TradingError.duplicateConflict }
            return existing
        }
        try validate(request)
        guard let quote = DemoMarket.instrument(request.symbol) else { throw TradingError.unknownInstrument }
        let fills = request.side == .buy ? request.limitPrice >= quote.price : request.limitPrice <= quote.price
        let order = Order(request: request, createdAt: now, status: fills ? .filled : .pending,
                          executionPrice: fills ? quote.price : nil)
        var updated = self
        if fills {
            let amount = quote.price * Int64(request.quantity)
            let positionIndex = positions.firstIndex { $0.symbol == request.symbol }
            if request.side == .buy {
                updated.cash -= amount
                if let index = positionIndex {
                    updated.positions[index].quantity += request.quantity
                    updated.positions[index].cost += amount
                } else {
                    updated.positions.append(.init(symbol: request.symbol, quantity: request.quantity, cost: amount))
                }
            } else if let index = positionIndex {
                updated.cash += amount
                let old = positions[index]
                let remaining = old.quantity - request.quantity
                // Decimal intermediate avoids overflowing a cost × quantity product.
                let remainingCost = NSDecimalNumber(decimal: Decimal(old.cost) * Decimal(remaining) / Decimal(old.quantity)).int64Value
                updated.realizedProfit += amount - (old.cost - remainingCost)
                updated.positions[index].cost = remainingCost
                updated.positions[index].quantity = remaining
                updated.positions.removeAll { $0.quantity == 0 }
            }
        }
        updated.orders.insert(order, at: 0)
        try updated.validateState()
        self = updated
        return order
    }

    public mutating func cancel(_ id: UUID) throws {
        try validateState()
        guard let index = orders.firstIndex(where: { $0.id == id }), orders[index].status == .pending else {
            throw TradingError.cannotCancel
        }
        orders[index].status = .cancelled
    }
}

/// Integration boundary, not a claimed connection to any broker.
/// A concrete adapter requires the chosen broker's published contract and authorization flow.
public protocol LiveBrokerGateway: Sendable {
    func submit(_ request: OrderRequest, confirmationToken: String) async throws -> String
    func cancel(brokerOrderID: String) async throws
}

public struct UnconfiguredBroker: LiveBrokerGateway {
    public init() {}
    public func submit(_ request: OrderRequest, confirmationToken: String) async throws -> String {
        throw TradingError.liveUnavailable
    }
    public func cancel(brokerOrderID: String) async throws { throw TradingError.liveUnavailable }
}
