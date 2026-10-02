import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject private var store: AppStore
    private var holdingFraction: Double {
        store.account.totalValue > 0 ? Double(store.account.holdingsValue) / Double(store.account.totalValue) : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Card {
                        HStack {
                            Text("TOPLAM VARLIK").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.toggleBalances() } label: {
                                Image(systemName: store.preferences.hidesBalances ? "eye.slash" : "eye")
                            }.accessibilityLabel(store.preferences.hidesBalances ? "Bakiyeleri göster" : "Bakiyeleri gizle")
                                .accessibilityIdentifier("balance-visibility")
                        }
                        Text(store.money(store.account.totalValue))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("total-balance")
                        HStack {
                            Text("Toplam kâr / zarar").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            profitText(store.account.totalProfit).font(.subheadline.weight(.semibold))
                        }
                        if !store.preferences.hidesBalances {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.raised)
                                    Capsule().fill(Palette.accent).frame(width: proxy.size.width * holdingFraction)
                                }
                            }.frame(height: 7).accessibilityHidden(true)
                            HStack {
                                Label("Hisse %\(Int((holdingFraction * 100).rounded()))", systemImage: "circle.fill").foregroundStyle(Palette.accent)
                                Spacer()
                                Text("Nakit %\(100 - Int((holdingFraction * 100).rounded()))").foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                    }
                    Card {
                        SectionHeading(title: "Hesap özeti")
                        InfoRow(title: "Kullanılabilir nakit", value: store.money(store.account.availableCash))
                        InfoRow(title: "Emirlere ayrılan nakit", value: store.money(store.account.reservedCash))
                        InfoRow(title: "Hisselerin değeri", value: store.money(store.account.holdingsValue))
                        Divider().overlay(Palette.line)
                        InfoRow(title: "Açık pozisyon kâr / zarar", value: store.money(store.account.unrealizedProfit))
                        InfoRow(title: "Gerçekleşen kâr / zarar", value: store.money(store.account.realizedProfit))
                    }
                    HStack {
                        SectionHeading(title: "Varlıklarım")
                        Spacer()
                        Text("\(store.account.positions.count) hisse").font(.caption).foregroundStyle(.secondary)
                    }
                    if store.account.positions.isEmpty {
                        EmptyState(title: "Portföyün boş", message: "Piyasa ekranında bir hisse seçerek ilk alış işlemini deneyebilirsin.", icon: "square.stack.3d.up")
                    }
                    ForEach(store.account.positions.sorted { $0.symbol < $1.symbol }) { position in
                        if let instrument = DemoMarket.instrument(position.symbol) {
                            NavigationLink(value: instrument) {
                                Card {
                                    HStack(spacing: 12) {
                                        StockBadge(symbol: position.symbol)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(position.symbol).font(.headline)
                                            Text("\(position.quantity) adet").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 6) {
                                            Text(store.money(instrument.price * Int64(position.quantity)))
                                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                            profitText(instrument.price * Int64(position.quantity) - position.cost).font(.caption)
                                        }
                                    }
                                    Divider().overlay(Palette.line)
                                    InfoRow(title: "Ortalama maliyet", value: store.money(position.averageCost))
                                    let reserved = position.quantity - store.account.availableShares(position.symbol)
                                    if reserved > 0 { InfoRow(title: "Emirlere ayrılan adet", value: "\(reserved)") }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("holding-\(position.symbol)")
                        }
                    }
                    Text("Deneme hesabı · Başlangıç varlıkları ve fiyatlar örnektir. Komisyon ve vergiler hesaplanmaz.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(Palette.background)
            .navigationTitle("Portföy").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { DataBadge() } }
            .navigationDestination(for: Instrument.self) { StockDetailView(instrument: $0) }
        }
    }

    private func profitText(_ amount: Int64) -> some View {
        Text((!store.preferences.hidesBalances && amount > 0 ? "+" : "") + store.money(amount))
            .foregroundStyle(store.preferences.hidesBalances ? Color.secondary : amount >= 0 ? Palette.positive : Palette.negative)
            .monospacedDigit()
    }
}

private enum OrderFilter: String, CaseIterable {
    case all = "Tümü", pending = "Bekleyen", filled = "Gerçekleşen", cancelled = "İptal"
    func includes(_ order: Order) -> Bool {
        switch self { case .all: true; case .pending: order.status == .pending; case .filled: order.status == .filled; case .cancelled: order.status == .cancelled }
    }
}

struct OrdersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingCancellation: Order?
    @State private var error: String?
    @State private var filter: OrderFilter = .all
    private var orders: [Order] { store.account.orders.filter { filter.includes($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("İşlemlerin.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            Text("\(store.account.pendingOrders.count) bekleyen · \(store.account.orders.count) toplam emir")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right").font(.title2).foregroundStyle(Palette.accent)
                    }.padding(.top, 8)
                    Picker("Emir filtresi", selection: $filter) {
                        ForEach(OrderFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("order-filter")
                    if orders.isEmpty {
                        EmptyState(title: filter == .all ? "Henüz işlem yok" : "Bu listede emir yok",
                                   message: filter == .all ? "Alış ve satış işlemlerin, durumlarıyla birlikte burada yer alacak." : "Diğer durumları görmek için filtreyi değiştirebilirsin.", icon: "tray")
                    }
                    ForEach(orders) { order in
                        Card {
                            HStack(spacing: 12) {
                                StockBadge(symbol: order.request.symbol)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(order.request.symbol).font(.headline)
                                    Text("\(order.request.side.title) · Limit emir").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 2)
                                Label(order.status.title, systemImage: statusIcon(order.status))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(order.status == .filled ? Palette.positive : .secondary)
                            }
                            InfoRow(title: "Adet × limit fiyat", value: "\(order.request.quantity) × \(Money.formatted(order.request.limitPrice))")
                            if let price = order.executionPrice {
                                InfoRow(title: "Gerçekleşen tutar", value: store.money(price * Int64(order.request.quantity)))
                                InfoRow(title: "Gerçekleşme fiyatı", value: Money.formatted(price))
                            } else if order.status == .pending {
                                InfoRow(title: order.request.side == .buy ? "Ayrılan nakit" : "Ayrılan adet",
                                        value: order.request.side == .buy ? store.money(order.request.limitPrice * Int64(order.request.quantity)) : "\(order.request.quantity)")
                            }
                            Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if order.status == .pending {
                                Divider().overlay(Palette.line)
                                Text("Örnek fiyat sabit olduğu için bu emir kendiliğinden gerçekleşmez. İptal ettiğinde ayrılan bakiye veya hisse serbest kalır.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button { pendingCancellation = order } label: {
                                    Label("Emri iptal et", systemImage: "xmark.circle")
                                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.negative)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }.accessibilityIdentifier("cancel-order")
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Palette.background).navigationTitle("Emirler").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { DataBadge() } }
            .alert("Emir iptal edilsin mi?", isPresented: Binding(
                get: { pendingCancellation != nil }, set: { if !$0 { pendingCancellation = nil } }
            ), presenting: pendingCancellation) { order in
                Button("Emri iptal et", role: .destructive) {
                    do { try store.cancel(order) } catch { self.error = error.localizedDescription }
                    pendingCancellation = nil
                }
                Button("Vazgeç", role: .cancel) { pendingCancellation = nil }
            } message: { order in
                Text("\(order.request.symbol) için \(order.request.quantity) adetlik \(order.request.side.title.lowercased()) emri iptal edilecek. Ayrılan nakit veya hisse yeniden kullanılabilir olacak.")
            }
            .alert("İşlem tamamlanamadı", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("Tamam") { error = nil } } message: { Text(error ?? "") }
        }
    }

    private func statusIcon(_ status: OrderStatus) -> String {
        switch status { case .filled: "checkmark.circle.fill"; case .pending: "clock"; case .cancelled: "xmark.circle" }
    }
}
