import SwiftUI
import Charts

struct PaperRootView: View {
    @StateObject private var paper = PaperStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $paper.selectedTab) {
            NavigationStack { PaperDashboard() }.tabItem { Label("Özet",systemImage:"square.grid.2x2") }.tag(0)
            NavigationStack { PaperMarketView() }.tabItem { Label("Piyasalar",systemImage:"chart.xyaxis.line") }.tag(1)
            NavigationStack { PaperPortfolioView() }.tabItem { Label("Portföy",systemImage:"square.stack.3d.up") }.tag(2)
            NavigationStack { PaperAssistantView() }.tabItem { Label("Asistan",systemImage:"text.bubble") }.tag(3).badge(paper.snapshot?.reviews.count ?? 0)
        }
        .environmentObject(paper)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await paper.refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("BorsaOpenReviews"))) { _ in paper.selectedTab = 3 }
        .alert("İşlem tamamlanamadı",isPresented:Binding(get:{paper.error != nil},set:{if !$0 {paper.error = nil}})) { Button("Tamam") { paper.error = nil } } message: { Text(paper.error ?? "") }
    }
}
private struct PaperPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @EnvironmentObject private var paper: PaperStore
    @State private var settings = false
    var body: some View {
        ScrollView { LazyVStack(alignment:.leading,spacing:20) {
            if let message = paper.connectionMessage { Label(message,systemImage:"network.slash").font(.caption).foregroundStyle(.orange) }
            content
        }.padding(20) }
            .background(Palette.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .refreshable { await paper.refresh() }
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Label(paper.connected ? "Sunucu bağlı" : paper.configured ? "Çevrimdışı" : "Bağlantı gerekli",systemImage:paper.connected ? "network" : "network.slash")
                        .font(.caption).foregroundStyle(paper.connected ? Palette.accent : .secondary).accessibilityIdentifier("paper-connection-state")
                }
                ToolbarItem(placement:.topBarTrailing) { Button { settings = true } label: { Image(systemName:"slider.horizontal.3") }.accessibilityLabel("Ayarlar").accessibilityIdentifier("paper-settings") }
            }.sheet(isPresented:$settings) { PaperSettingsView() }
    }
}
struct PaperDashboard: View {
    @EnvironmentObject private var paper: PaperStore
    var body: some View {
        PaperPage(title:"Borsa") {
            VStack(alignment:.leading,spacing:8) {
                Text("Genel bakış").font(.system(.largeTitle,design:.rounded,weight:.semibold))
                Text("Gerçek kaynaklar · Sanal hesap").foregroundStyle(.secondary)
            }.padding(.top,8)
            if let snapshot = paper.snapshot {
                Card {
                    Label(snapshot.settings.modeTitle,systemImage:snapshot.settings.mode == "auto" ? "bolt.shield" : "pause.circle").font(.title2.weight(.semibold)).foregroundStyle(Palette.accent)
                    Text(paper.connected ? "Son kontrol: \(PaperFormat.date(snapshot.lastCycleAt))" : "Son alınan kayıt: \(PaperFormat.date(snapshot.serverTime)). İşlem için bağlantı bekleniyor.").font(.caption).foregroundStyle(.secondary)
                    Picker("Otomasyon",selection:Binding(get:{snapshot.settings.mode},set:{ mode in Task { _ = await paper.mutate("settings",method:"PATCH",values:["mode":mode]) } })) {
                        Text("Duraklat").tag("paused"); Text("İncele").tag("review"); Text("Otomatik").tag("auto")
                    }.pickerStyle(.segmented).disabled(!paper.canAct).accessibilityIdentifier("automation-mode")
                    Text("Otomatik modda yalnızca haber, fiyat ve risk kuralları birlikte uygunsa işlem yapılır. Belirsiz kararlar incelemeye gelir.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(snapshot.wallets) { wallet in WalletCard(wallet:wallet) }
                Button { paper.selectedTab = 3 } label: {
                    Card { HStack { Label("İnceleme bekleyen",systemImage:"tray"); Spacer(); Text("\(snapshot.reviews.count)").font(.title2.bold()); Image(systemName:"arrow.right") } }
                }.buttonStyle(.plain).accessibilityIdentifier("open-reviews")
                if let decision = snapshot.decisions.first {
                    Card { SectionHeading(title:"Son karar"); Text("\(decision.symbol) · \(decision.action)").font(.headline); Text(decision.reason).font(.subheadline); Text(decision.stateTitle).font(.caption).foregroundStyle(.secondary) }
                }
                SectionHeading(title:"Veri bağlantıları")
                ForEach(snapshot.health) { provider in
                    Card { HStack { Text(provider.name).font(.headline); Spacer(); Image(systemName:provider.status == "connected" ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(provider.status == "connected" ? Palette.accent : .orange) }; Text(provider.message).font(.subheadline).foregroundStyle(.secondary); if provider.lastSuccessAt != nil { Text("Son veri: \(PaperFormat.date(provider.lastSuccessAt))").font(.caption).foregroundStyle(.secondary) } }
                }
            } else {
                EmptyState(title:"Gerçek veriye bağlan",message:"Güvenli sunucu bağlantısını Ayarlar’dan eşleştir. Veri gelene kadar fiyat veya grafik üretilmez.",icon:"network")
                Card { Label("Eski hesabın korundu",systemImage:"externaldrive.badge.checkmark").font(.headline); Text("Örnek verili deneme hesabı ayrı saklanıyor. Yeni sanal hesap TL ve USD bakiyeleriyle, sıfır pozisyonla başlar.").font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }
}
private struct WalletCard: View {
    let wallet: PaperWallet
    @EnvironmentObject private var legacy: AppStore
    private func money(_ cents: Int64?) -> String { legacy.preferences.hidesBalances ? "••••••" : PaperFormat.money(cents,wallet.currency) }
    var body: some View {
        Card {
            HStack { Text(wallet.currency == "TRY" ? "Türk lirası hesabı" : "Dolar hesabı").font(.headline); Spacer(); Text("SANAL").font(.caption2.weight(.semibold)).foregroundStyle(Palette.accent) }
            Text(money(wallet.totalCents)).font(.system(.largeTitle,design:.rounded,weight:.semibold)).minimumScaleFactor(0.6).lineLimit(1)
            InfoRow(title:"Kullanılabilir nakit",value:money(wallet.availableCents))
            InfoRow(title:"Maliyet sonrası kâr / zarar",value:money(wallet.netProfitCents))
            if wallet.totalCents == nil { Text("Varlık fiyatlarından biri güncel değil; toplam ve getiri hesaplanmıyor.").font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct PaperMarketView: View {
    @EnvironmentObject private var paper: PaperStore
    @State private var market = "BIST"
    @State private var search = ""
    @State private var onlyWatchlist = false
    private var items: [PaperInstrument] {
        (paper.snapshot?.instruments ?? []).filter { item in
            item.market == market && (!onlyWatchlist || paper.snapshot?.watchlist.contains(item.symbol) == true) && (search.isEmpty || (item.symbol+" "+item.name+" "+item.sector).folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"tr_TR")).contains(search.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"tr_TR"))))
        }.sorted { $0.symbol < $1.symbol }
    }
    var body: some View {
        PaperPage(title:"Piyasalar") {
            Picker("Piyasa",selection:$market) { Text("BIST").tag("BIST"); Text("ABD").tag("US") }.pickerStyle(.segmented).accessibilityIdentifier("paper-market-picker")
            HStack { Image(systemName:"magnifyingglass"); TextField("Hisse, şirket veya sektör",text:$search).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("paper-search") }.padding(16).background(Palette.surface,in:RoundedRectangle(cornerRadius:18))
            Toggle("Yalnızca takip ettiklerim",isOn:$onlyWatchlist).font(.subheadline)
            if items.isEmpty { EmptyState(title:"Gösterilecek hisse yok",message:paper.configured ? "Aramanı veya bağlantı durumunu kontrol et." : "Sunucuya bağlandığında izleme evreni burada görünür.",icon:"chart.xyaxis.line") }
            ForEach(items) { item in
                NavigationLink(value:item.symbol) {
                    Card {
                        HStack(spacing:12) { StockBadge(symbol:item.symbol); VStack(alignment:.leading,spacing:5) { Text(item.symbol).font(.headline); Text(item.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(PaperFormat.price(item.quote?.priceUnits,item.currency)).font(.headline).monospacedDigit() }
                        if let q = item.quote { QuoteProvenance(quote:q) } else { Text("Veri yok · örnek fiyat kullanılmıyor").font(.caption).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("paper-stock-\(item.symbol)")
            }
        }.navigationDestination(for:String.self) { PaperStockDetail(symbol:$0) }
    }
}
private struct QuoteProvenance: View {
    let quote: PaperQuote
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(quote.source)
            Text("Kaynak saati: \(PaperFormat.date(quote.timestamp))")
            Text(quote.quality == "eod" ? "Gün sonu veri · gün içi işlem kapalı" : "Bildirilen gecikme: \(quote.delaySeconds) sn · \(quote.fresh ? "güncel" : "güncel değil")")
        }.font(.caption).foregroundStyle(quote.fresh ? Color.secondary : Color.orange)
    }
}
struct PaperStockDetail: View {
    let symbol: String
    @EnvironmentObject private var paper: PaperStore
    @State private var side: OrderSide?
    private var item: PaperInstrument? { paper.snapshot?.instruments.first { $0.symbol == symbol } }
    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text(item.name).font(.title2.weight(.semibold)); Text(item.sector).foregroundStyle(.secondary)
                        Text(PaperFormat.price(item.quote?.priceUnits,item.currency)).font(.system(size:40,weight:.semibold,design:.rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        if let q = item.quote { Card { QuoteProvenance(quote:q) } }
                        if item.history.count > 1 {
                            Card {
                                Text("Alınan gerçek fiyatlar").font(.headline)
                                Chart(item.history) { point in LineMark(x:.value("Saat",Date(timeIntervalSince1970:point.at/1000)),y:.value("Fiyat",Double(point.priceUnits)/10000)).foregroundStyle(Palette.accent) }.frame(height:180)
                            }
                        } else { EmptyState(title:"Fiyat geçmişi bekleniyor",message:"Grafik yalnızca kaynaktan alınmış fiyat noktalarıyla oluşur.",icon:"chart.xyaxis.line") }
                        if let reason = item.blockedReason { Label(reason,systemImage:"pause.circle").font(.subheadline).foregroundStyle(.orange) }
                        Card { InfoRow(title:"Pozisyonun",value:"\(paper.snapshot?.positions.first { $0.symbol == symbol }?.quantity ?? 0) adet"); InfoRow(title:"Para birimi",value:item.currency) }
                    }.padding(20)
                }.background(Palette.background)
                .safeAreaInset(edge:.bottom) {
                    HStack { Button("Sat") { side = .sell }.buttonStyle(ActionButtonStyle(prominent:false)).accessibilityIdentifier("paper-sell"); Button("Al") { side = .buy }.buttonStyle(ActionButtonStyle()).accessibilityIdentifier("paper-buy") }
                        .disabled(!paper.canAct || item.blockedReason != nil || item.quote?.fresh != true).padding(20).background(.regularMaterial)
                }
                .sheet(item:$side) { PaperOrderSheet(item:item,initialSide:$0) }
            } else { EmptyState(title:"Hisse verisi yok",message:"Sunucu bağlantısını kontrol et.",icon:"network.slash") }
        }.navigationTitle(symbol).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button { Task { var list = paper.snapshot?.watchlist ?? []; if list.contains(symbol) { list.removeAll {$0 == symbol} } else { list.append(symbol) }; _ = await paper.mutate("watchlist",method:"PUT",values:["symbols":list]) } } label: { Image(systemName:paper.snapshot?.watchlist.contains(symbol) == true ? "star.fill" : "star") }.disabled(!paper.canAct).accessibilityLabel("Takip listesi") } }
    }
}
struct PaperPortfolioView: View {
    @EnvironmentObject private var paper: PaperStore
    var body: some View {
        PaperPage(title:"Portföy") {
            if let snapshot = paper.snapshot {
                ForEach(snapshot.wallets) { wallet in
                    WalletCard(wallet:wallet)
                    Card {
                        InfoRow(title:"Ödenen komisyon",value:PaperFormat.money(wallet.feesCents,wallet.currency))
                        InfoRow(title:"Gerçekleşen net kâr / zarar",value:PaperFormat.money(wallet.realizedCents,wallet.currency))
                        InfoRow(title:"Emirlere ayrılan",value:PaperFormat.money(wallet.reservedCents,wallet.currency))
                        InfoRow(title:"Zirveden düşüş",value:wallet.drawdownPercent.map { String(format:"%%%.2f",$0) } ?? "—")
                    }
                }
                Text("TL ve USD ayrı hesaplanır. Komisyon maliyete dahildir; fiyat kayması gerçekleşme fiyatına uygulanır.").font(.caption).foregroundStyle(.secondary)
                SectionHeading(title:"Varlıklar")
                if snapshot.positions.isEmpty { Text("Henüz pozisyonun yok.").foregroundStyle(.secondary) }
                ForEach(snapshot.positions) { p in
                    Card { Text("\(p.symbol) · \(p.quantity) adet").font(.headline); InfoRow(title:"Güncel değer",value:PaperFormat.money(p.marketValueCents,p.currency)); InfoRow(title:"Maliyet",value:PaperFormat.money(p.costCents,p.currency)); InfoRow(title:"Net açık kâr / zarar",value:PaperFormat.money(p.profitCents,p.currency)) }
                }
                SectionHeading(title:"Emirler",subtitle:"Limit emirler 15 dakika geçerlidir.")
                if snapshot.orders.isEmpty { Text("Henüz emir yok.").foregroundStyle(.secondary) }
                ForEach(snapshot.orders.prefix(100)) { order in
                    let currency = snapshot.instruments.first { $0.symbol == order.symbol }?.currency ?? "USD"
                    Card {
                        HStack { Text("\(order.symbol) · \(order.side == "buy" ? "Alış" : "Satış")").font(.headline); Spacer(); Text(order.statusTitle).font(.caption).foregroundStyle(Palette.accent) }
                        InfoRow(title:"Adet / gerçekleşen",value:"\(order.quantity) / \(order.filledQty)")
                        InfoRow(title:"Limit",value:PaperFormat.price(order.limitUnits,currency))
                        if order.executionUnits != nil { InfoRow(title:"Ortalama gerçekleşme",value:PaperFormat.price(order.executionUnits,currency)); InfoRow(title:"Komisyon",value:PaperFormat.money(order.feesCents,currency)) }
                        Text(order.reason).font(.caption).foregroundStyle(.secondary)
                        if !order.source.isEmpty { Text(order.source).font(.caption).foregroundStyle(.secondary) }
                        Text(PaperFormat.date(order.createdAt)).font(.caption).foregroundStyle(.secondary)
                        if order.status == "pending" { Button("Emri iptal et",role:.destructive) { Task { _ = await paper.mutate("orders/\(order.id)/cancel") } }.disabled(!paper.canAct) }
                    }
                }
            } else { EmptyState(title:"Hesap bağlantısı bekleniyor",message:"Sanal hesabın sunucuda saklanır. Bağlantı kurulduğunda bakiye ve emirler eşitlenir.",icon:"externaldrive") }
        }
    }
}
struct PaperAssistantView: View {
    @EnvironmentObject private var paper: PaperStore
    @State private var reviewsOnly = true
    var body: some View {
        PaperPage(title:"Asistan") {
            Text("Kararların gerekçesi").font(.title.weight(.semibold))
            Text("Kaynaklı kural analizi · Sonuçlar bir kazanç tahmini değildir.").font(.caption).foregroundStyle(.secondary)
            Picker("Liste",selection:$reviewsOnly) { Text("İncelemeler").tag(true); Text("Tüm kararlar").tag(false) }.pickerStyle(.segmented)
            let decisions = reviewsOnly ? paper.snapshot?.reviews ?? [] : paper.snapshot?.decisions ?? []
            if decisions.isEmpty { EmptyState(title:"Bekleyen karar yok",message:"Yeni haberler değerlendirilir. Belirsiz bir karar oluştuğunda kaynaklarıyla burada görünür.",icon:"checkmark.bubble") }
            ForEach(decisions.prefix(100)) { decision in
                NavigationLink { PaperDecisionDetail(id:decision.id) } label: {
                    Card { HStack { Text("\(decision.symbol) · \(decision.action)").font(.headline); Spacer(); Text(decision.stateTitle).font(.caption).foregroundStyle(Palette.accent) }; Text(decision.reason).font(.subheadline); Text("\(decision.source) · \(PaperFormat.date(decision.createdAt))").font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain)
            }
            SectionHeading(title:"Haber akışı")
            if paper.snapshot?.news.isEmpty != false { Text("Henüz haber alınmadı. Bağlantı durumunu Özet ekranından takip edebilirsin.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach((paper.snapshot?.news ?? []).prefix(50)) { news in
                Card {
                    Text(news.title).font(.headline)
                    if !news.summary.isEmpty { Text(news.summary).font(.subheadline).lineLimit(5) }
                    Text("\(news.source) · \(PaperFormat.date(news.publishedAt))").font(.caption).foregroundStyle(.secondary)
                    Text("İlk alınma: \(PaperFormat.date(news.receivedAt)) · Yayından alınmaya \(news.delaySeconds / 60) dk").font(.caption2).foregroundStyle(.secondary)
                    if let url = URL(string:news.url), url.scheme == "https" { Link("Kaynağı aç",destination:url).font(.subheadline) }
                }
            }
        }
    }
}
private struct PaperDecisionDetail: View {
    let id: String
    @EnvironmentObject private var paper: PaperStore
    @State private var preview: PaperPreview?
    private var decision: PaperDecision? { paper.snapshot?.decisions.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let d = decision {
                VStack(alignment:.leading,spacing:20) {
                    Text("\(d.symbol) · \(d.action)").font(.largeTitle.weight(.semibold))
                    Text(d.stateTitle).foregroundStyle(Palette.accent)
                    if let news = paper.snapshot?.news.first(where:{ $0.id == d.newsId }) { Text(news.title).font(.headline) }
                    Card { SectionHeading(title:"Şirkete etkisi"); Text(d.companyImpact); SectionHeading(title:"Sektöre etkisi"); Text(d.sectorImpact); SectionHeading(title:"Portföyüne etkisi"); Text(d.portfolioImpact) }
                    Card { Text(d.reason); Text("Analiz: \(d.analysisVersion) · \(PaperFormat.date(d.createdAt))").font(.caption).foregroundStyle(.secondary); if let url = URL(string:d.sourceURL),url.scheme == "https" { Link("\(d.source) kaynağını aç",destination:url) } }
                    if d.state == "review" && d.expiresAt > Date().timeIntervalSince1970 * 1000 {
                        Text("Son yanıt: \(PaperFormat.date(d.expiresAt)). Yanıt gelmezse işlem yapılmaz.").font(.subheadline).foregroundStyle(.orange)
                        Text("Alış, hesabın en fazla %2,5'i ve risk sınırlarıyla; satış, satılabilir adetle hesaplanır. Onayda güncel fiyat ve tüm sınırlar yeniden kontrol edilir.").font(.caption).foregroundStyle(.secondary)
                        HStack { Button("Alışı değerlendir") { Task { preview = await paper.preview(decisionID:id,side:"buy") } }.buttonStyle(ActionButtonStyle()); Button("Satışı değerlendir") { Task { preview = await paper.preview(decisionID:id,side:"sell") } }.buttonStyle(ActionButtonStyle(prominent:false)) }.disabled(!paper.canAct)
                        Button("İşlem yapma",role:.destructive) { Task { _ = await paper.mutate("decisions/\(id)/review",values:["choice":"reject"]) } }.disabled(!paper.canAct).frame(maxWidth:.infinity,minHeight:44)
                    }
                }.padding(20)
            }
        }.background(Palette.background).navigationTitle("Değerlendirme").navigationBarTitleDisplayMode(.inline)
        .sheet(item:$preview) { value in
            NavigationStack {
                VStack(spacing:20) {
                    Card {
                        Text("\(value.symbol) · \(value.side == "buy" ? "Sanal alış" : "Sanal satış")").font(.title2)
                        InfoRow(title:"Adet",value:"\(value.quantity)")
                        InfoRow(title:"Limit",value:PaperFormat.price(value.limitUnits,value.currency))
                        InfoRow(title:"Limitte komisyon",value:PaperFormat.money(value.feeCents,value.currency))
                        InfoRow(title:value.side == "buy" ? "En fazla ödeme" : "En az net gelir",value:PaperFormat.money(value.grossCents + (value.side == "buy" ? value.feeCents : -value.feeCents),value.currency))
                    }
                    Text("Önizleme 30 saniye geçerli. Fiyat veya masraf değişirse tekrar gözden geçirmen gerekir.").font(.caption).foregroundStyle(.secondary)
                    Button("Sanal emri onayla") { Task { if await paper.mutate("decisions/\(id)/review",values:["choice":value.side,"confirmation":value.confirmation]) { preview=nil } } }.buttonStyle(ActionButtonStyle()).disabled(!paper.canAct)
                    Spacer()
                }.padding(20).background(Palette.background).navigationTitle("Emir önizlemesi")
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Vazgeç") { preview=nil } } }
            }.presentationDetents([.medium,.large])
        }
    }
}
struct PaperOrderSheet: View {
    let item: PaperInstrument
    let initialSide: OrderSide
    @EnvironmentObject private var paper: PaperStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = "1"
    @State private var price = ""
    @State private var review = false
    @State private var accepted = false
    @State private var requestID = UUID().uuidString
    @FocusState private var focused: Bool
    private var units: Int64? { PaperFormat.parsePrice(price) }
    private var count: Int? { Int(quantity) }
    private var valid: Bool { (count ?? 0)>0 && (count ?? 0)<=100000 && units != nil && paper.canAct }
    private var amount: Int64? { guard let units,let count,count>0,count<=100000 else{return nil};return (units*Int64(count)+99)/100 }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text(item.name).font(.title2.weight(.semibold))
                    Text("Sanal \(initialSide.title.lowercased()) · \(item.currency)").foregroundStyle(Palette.accent)
                    if accepted { EmptyState(title:"Emir sıraya alındı",message:"Karar anından sonraki uygun kotasyon bekleniyor. Durumunu Portföy ekranından izleyebilirsin.",icon:"checkmark.circle") }
                    else if review {
                        Card { InfoRow(title:"Adet",value:quantity); InfoRow(title:"Limit fiyat",value:PaperFormat.price(units,item.currency)); InfoRow(title:"Limit tutarı",value:PaperFormat.money(amount,item.currency)); Text("Komisyon: \(paper.snapshot?.settings.commissionBps ?? 0) baz puan. Kayma: \(paper.snapshot?.settings.slippageBps ?? 0) baz puan. Emir 15 dakika geçerli.").font(.caption).foregroundStyle(.secondary) }
                        Button("Sanal emri onayla") { Task { guard let count,let units else{return};accepted=await paper.mutate("orders",values:["id":requestID,"symbol":item.symbol,"side":initialSide.rawValue,"quantity":count,"limitUnits":units]) } }.buttonStyle(ActionButtonStyle()).disabled(!valid).accessibilityIdentifier("paper-confirm-order")
                        Button("Düzenle") {review=false}.frame(maxWidth:.infinity,minHeight:44)
                    } else {
                        Card {
                            Text("Adet").font(.caption).foregroundStyle(.secondary)
                            TextField("Adet",text:$quantity).keyboardType(.numberPad).font(.largeTitle).focused($focused).accessibilityIdentifier("paper-order-quantity")
                            Divider()
                            Text("Limit fiyat").font(.caption).foregroundStyle(.secondary)
                            TextField("Limit fiyat",text:$price).keyboardType(.decimalPad).font(.largeTitle).focused($focused).accessibilityIdentifier("paper-order-price")
                        }
                        if let q = item.quote { QuoteProvenance(quote:q) }
                        Text("Emir masraf ve risk sınırlarıyla kontrol edilir; karar anındaki eski fiyatla gerçekleşmez.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Emri gözden geçir") { focused=false;review=true }.buttonStyle(ActionButtonStyle()).disabled(!valid)
                    }
                }.padding(20)
            }.background(Palette.background).navigationTitle(item.symbol).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarLeading) {Button(accepted ? "Bitti" : "Vazgeç") {dismiss()}}; ToolbarItem(placement:.topBarTrailing) {if focused {Button("Klavyeyi kapat") {focused=false}}} }
            .onAppear { let value = initialSide == .buy ? item.quote?.askUnits : item.quote?.bidUnits; if let value { price=String(format:"%.4f",Double(value)/10000*(initialSide == .buy ? 1.002 : 0.998)).replacingOccurrences(of:".",with:",") } }
        }
    }
}
