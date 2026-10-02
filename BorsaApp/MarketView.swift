import SwiftUI

struct MarketView: View {
    let watchlistOnly: Bool
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var sort: MarketSort = .symbol
    @State private var showPreferences = false
    @FocusState private var searching: Bool

    private var instruments: [Instrument] {
        MarketQuery.find(DemoMarket.instruments.filter {
            !watchlistOnly || store.watchlist.contains($0.symbol)
        }, query: search, sort: sort)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(watchlistOnly ? "Senin radarın." : "Piyasaya yakından.")
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            Text(watchlistOnly ? "İlgilendiğin şirketler, bir arada." : "Hisselerini izle, kararlarını dene.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.top, 8)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Hisse, şirket veya sektör", text: $search)
                            .font(.subheadline).autocorrectionDisabled().textInputAutocapitalization(.characters)
                            .focused($searching).submitLabel(.search)
                            .onSubmit { searching = false }.accessibilityIdentifier("market-search")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .foregroundStyle(.secondary).accessibilityLabel("Aramayı temizle")
                        }
                    }
                    .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                    if !watchlistOnly && search.isEmpty && !searching { featuredCard }
                    HStack {
                        SectionHeading(title: watchlistOnly ? "Takip listem" : "Hisseler")
                        Spacer()
                        Menu {
                            Picker("Sıralama", selection: $sort) {
                                ForEach(MarketSort.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label(sort.title, systemImage: "arrow.up.arrow.down")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }.accessibilityIdentifier("market-sort")
                    }
                    if instruments.isEmpty {
                        EmptyState(title: search.isEmpty ? "Radarını oluştur" : "Sonuç bulunamadı",
                                   message: search.isEmpty ? "Hisse detayındaki yıldıza dokunarak şirketleri buraya ekle." : "Hisse kodu, şirket adı veya sektör ile tekrar dene.",
                                   icon: search.isEmpty ? "star" : "magnifyingglass")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(instruments) { instrument in
                                NavigationLink(value: instrument) { StockRow(instrument: instrument) }
                                    .buttonStyle(.plain).accessibilityIdentifier("stock-\(instrument.symbol)")
                                if instrument.id != instruments.last?.id { Divider().overlay(Palette.line).padding(.leading, 56) }
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 2)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle")
                        Text("\(instruments.count) hisse · Sabit örnek fiyatlar")
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
            .navigationTitle(watchlistOnly ? "Takip" : "Borsa").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DataBadge() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPreferences = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Ayarlar").accessibilityIdentifier("open-settings")
                }
            }
            .sheet(isPresented: $showPreferences) { PreferencesView() }
            .navigationDestination(for: Instrument.self) { StockDetailView(instrument: $0) }
        }
    }

    private var featuredCard: some View {
        let instrument = DemoMarket.instruments[0]
        return NavigationLink(value: instrument) {
            Card {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YAKIN BAKIŞ").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Palette.accent)
                        Text(instrument.name).font(.headline)
                    }
                    Spacer()
                    Text(instrument.symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Money.formatted(instrument.price)).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    ChangeLabel(percent: instrument.changePercent)
                }
                PriceChart(instrument: instrument, compact: true).frame(height: 38).padding(.vertical, 5)
                Divider().overlay(Palette.line)
                HStack { Text("Hisseyi incele"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
            }.contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityIdentifier("featured-detail")
    }
}

struct StockDetailView: View {
    let instrument: Instrument
    @EnvironmentObject private var store: AppStore
    @State private var orderSide: OrderSide?
    private var position: Position? { store.account.positions.first { $0.symbol == instrument.symbol } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    StockBadge(symbol: instrument.symbol)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(instrument.name).font(.headline)
                        Text(instrument.sector).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.formatted(instrument.price)).font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 4)
                    ChangeLabel(percent: instrument.changePercent)
                }
                Card { PriceChart(instrument: instrument) }
                Card {
                    SectionHeading(title: "Hissedeki durumun")
                    InfoRow(title: "Toplam adet", value: "\(position?.quantity ?? 0)")
                    InfoRow(title: "Satılabilir adet", value: "\(store.account.availableShares(instrument.symbol))")
                    if let position {
                        InfoRow(title: "Ortalama maliyet", value: store.money(position.averageCost))
                        InfoRow(title: "Güncel değer", value: store.money(Int64(position.quantity) * instrument.price))
                    }
                    InfoRow(title: "Kullanılabilir nakit", value: store.money(store.account.availableCash))
                }
                Card {
                    SectionHeading(title: "Hisse bilgileri")
                    InfoRow(title: "Örnek önceki kapanış", value: Money.formatted(instrument.previousClose))
                    InfoRow(title: "Sektör", value: instrument.sector)
                    Label("Fiyat ve grafikler örnektir. Grafik gerçek fiyat geçmişi göstermez.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
        .background(Palette.background)
        .navigationTitle(instrument.symbol).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleWatch(instrument.symbol) } label: {
                    Image(systemName: store.watchlist.contains(instrument.symbol) ? "star.fill" : "star")
                }.accessibilityLabel(store.watchlist.contains(instrument.symbol) ? "Takipten çıkar" : "Takibe al")
                    .accessibilityIdentifier("toggle-watch")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    Button("Sat") { orderSide = .sell }.buttonStyle(ActionButtonStyle(prominent: false))
                        .accessibilityIdentifier("demo-sell")
                    Button("Al") { orderSide = .buy }.buttonStyle(ActionButtonStyle())
                        .accessibilityIdentifier("demo-buy")
                }
                Text("Deneme hesabı · Gerçek emir gönderilmez").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
        }
        .sheet(item: $orderSide) { side in OrderTicket(instrument: instrument, initialSide: side) }
    }
}

extension OrderSide: Identifiable { public var id: String { rawValue } }
