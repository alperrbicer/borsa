import SwiftUI

struct OrderTicket: View {
    let instrument: Instrument
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = "1"
    @State private var price: String
    @State private var side: OrderSide
    @State private var review: OrderRequest?
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?
    private enum Field { case quantity, price }

    init(instrument: Instrument, initialSide: OrderSide) {
        self.instrument = instrument
        _side = State(initialValue: initialSide)
        _price = State(initialValue: Money.editable(instrument.price))
    }

    private var draft: OrderRequest? {
        guard let amount = Int(quantity), let limit = Money.parse(price) else { return nil }
        return OrderRequest(symbol: instrument.symbol, side: side, quantity: amount, limitPrice: limit)
    }
    private var maximumQuantity: Int {
        if side == .sell { return min(100_000, store.account.availableShares(instrument.symbol)) }
        guard let limit = Money.parse(price), limit > 0 else { return 0 }
        let owned = store.account.positions.first { $0.symbol == instrument.symbol }?.quantity ?? 0
        return Int(min(100_000, Int64(1_000_000 - owned), store.account.availableCash / limit))
    }
    private var amount: Int64? {
        guard let draft, (1...100_000).contains(draft.quantity), (1...100_000_000).contains(draft.limitPrice) else { return nil }
        return draft.limitPrice * Int64(draft.quantity)
    }
    private var fillsImmediately: Bool? {
        guard let draft, amount != nil else { return nil }
        return side == .buy ? draft.limitPrice >= instrument.price : draft.limitPrice <= instrument.price
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        StockBadge(symbol: instrument.symbol)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(instrument.name).font(.headline)
                            Text("Örnek son fiyat · \(Money.formatted(instrument.price))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 8)
                    Picker("İşlem", selection: $side) {
                        ForEach(OrderSide.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("order-side")
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Adet").font(.subheadline).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline) {
                                TextField("1", text: $quantity).keyboardType(.numberPad)
                                    .font(.system(.largeTitle, design: .rounded, weight: .medium)).monospacedDigit()
                                    .focused($focusedField, equals: .quantity)
                                    .accessibilityLabel("Emir adedi").accessibilityIdentifier("order-quantity")
                                Text("adet").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach([25, 50, 100], id: \.self) { percent in
                                Button(percent == 100 ? "Tümü" : "%\(percent)") {
                                    quantity = String(min(maximumQuantity, max(1, maximumQuantity * percent / 100)))
                                    focusedField = nil
                                }
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                                .disabled(maximumQuantity < 1)
                                .accessibilityLabel(percent == 100 ? "Maksimum adet" : "%\(percent)")
                                .accessibilityIdentifier("quantity-\(percent)")
                            }
                        }
                        Text("Bu limitte en fazla \(maximumQuantity) adet")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("quantity-available")
                        Divider().overlay(Palette.line)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Limit fiyat").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Button("Son fiyatı kullan") { price = Money.editable(instrument.price) }
                                    .font(.caption).accessibilityIdentifier("use-last-price")
                            }
                            HStack(alignment: .firstTextBaseline) {
                                TextField("0,00", text: $price).keyboardType(.decimalPad)
                                    .font(.system(.title, design: .rounded, weight: .medium)).monospacedDigit()
                                    .focused($focusedField, equals: .price)
                                    .accessibilityLabel("Limit fiyatı").accessibilityIdentifier("order-price")
                                Text("TL").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Card {
                        InfoRow(title: side == .buy ? "Kullanılabilir nakit" : "Satılabilir adet",
                                value: side == .buy ? store.money(store.account.availableCash) : "\(store.account.availableShares(instrument.symbol))")
                        InfoRow(title: "Limit tutarı", value: amount.map { Money.formatted($0) } ?? "—")
                        if let fills = fillsImmediately {
                            Label(fills ? "Bu fiyatla örnek son fiyattan gerçekleşir." : "Limit örnek fiyata ulaşmıyor; emir bekler.",
                                  systemImage: fills ? "checkmark.circle" : "clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(Palette.negative).accessibilityIdentifier("order-error")
                    }
                    Text("Deneme hesabı · Komisyon ve vergi hesaplanmaz. Sonraki adımda emri kontrol edip onaylayacaksın.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(Palette.background)
            .navigationTitle("\(instrument.symbol) · \(side.title)").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Emri gözden geçir") {
                    focusedField = nil
                    guard let draft else {
                        validationMessage = "Geçerli bir adet ve limit fiyat gir. Örnek: 10 adet, 312,50 TL."
                        return
                    }
                    do { try store.account.validate(draft); validationMessage = nil; review = draft }
                    catch { validationMessage = error.localizedDescription }
                }.buttonStyle(ActionButtonStyle()).accessibilityIdentifier("review-order")
                    .padding(20).background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if focusedField != nil { Button("Bitti") { focusedField = nil } }
                }
            }
            .onChange(of: quantity) { _, _ in validationMessage = nil }
            .onChange(of: price) { _, _ in validationMessage = nil }
            .onChange(of: side) { _, _ in validationMessage = nil }
            .navigationDestination(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
                if let review { OrderReview(request: review) { dismiss() } }
            }
        }.interactiveDismissDisabled(review != nil)
    }
}

struct OrderReview: View {
    let request: OrderRequest
    let onComplete: () -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: Order?
    @State private var error: String?
    @State private var submitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: receipt == nil ? "checklist" : receipt?.status == .filled ? "checkmark.circle.fill" : "clock.badge.checkmark")
                    .font(.system(size: 36)).foregroundStyle(Palette.accent)
                    .frame(width: 72, height: 72).background(Palette.raised, in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    Text(receipt == nil ? "Son bir kontrol." : receipt?.status == .filled ? "İşlemin gerçekleşti." : "Emrin kaydedildi.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .accessibilityIdentifier(receipt == nil ? "order-review-title" : "order-success")
                    Text(receipt == nil ? "Onayladığında deneme hesabında işlem yapılır. Gerçek emir gönderilmez." : receipt?.status == .filled ? "Bakiyen ve portföyün güncellendi. İşlemi emir geçmişinde bulabilirsin." : "Emrin bekliyor. Örnek fiyat sabittir; ayrılan nakit veya hisseyi iptal ederek serbest bırakabilirsin.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Card {
                    InfoRow(title: "Hisse", value: request.symbol)
                    InfoRow(title: "İşlem", value: "\(request.side.title) · Limit")
                    InfoRow(title: "Adet", value: "\(request.quantity)")
                    InfoRow(title: "Limit fiyatı", value: Money.formatted(request.limitPrice))
                    Divider().overlay(Palette.line)
                    InfoRow(title: "Limit tutarı", value: Money.formatted(request.limitPrice * Int64(request.quantity)))
                    if let execution = receipt?.executionPrice {
                        InfoRow(title: "Gerçekleşme fiyatı", value: Money.formatted(execution))
                        InfoRow(title: "Gerçekleşen tutar", value: Money.formatted(execution * Int64(request.quantity)))
                    }
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Palette.negative) }
            }.padding(24)
        }
        .background(Palette.background)
        .navigationTitle(receipt == nil ? "Emir onayı" : "İşlem sonucu").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if receipt != nil {
                    Button("Tamam", action: onComplete).accessibilityIdentifier("close-receipt")
                } else {
                    Button(submitting ? "Kaydediliyor…" : "Deneme emrini onayla") {
                        guard !submitting else { return }
                        submitting = true
                        do { receipt = try store.submit(request) }
                        catch { self.error = error.localizedDescription }
                        submitting = false
                    }.disabled(submitting).accessibilityIdentifier("confirm-demo-order")
                }
            }.buttonStyle(ActionButtonStyle()).padding(20).background(.regularMaterial)
        }
        .toolbar {
            if receipt == nil { ToolbarItem(placement: .topBarLeading) { Button("Düzenle") { dismiss() } } }
        }
    }
}
