import SwiftUI
import UniformTypeIdentifiers
struct PaperSettingsView: View {
    @EnvironmentObject private var paper: PaperStore
    @EnvironmentObject private var legacy: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var exporting = false
    @State private var document = BackupDocument(data:Data())
    @State private var positionLimit = 10
    @State private var dailyLoss = 2
    @State private var commission = 10
    @State private var slippage = 5
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Card {
                        Label("Sunucu bağlantısı",systemImage:"lock.shield").font(.headline)
                        TextField("https://sunucun.local:8787",text:$paper.serverURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("paper-server-url")
                        DisclosureGroup("Sertifika parmak izi") { TextField("SHA-256",text:$paper.serverPin).font(.caption.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        SecureField("Tek kullanımlık eşleşme kodu",text:$code).keyboardType(.numberPad).accessibilityIdentifier("paper-pair-code")
                        Button(paper.busy ? "Bağlanıyor…" : "Güvenli bağlan") { Task { await paper.pair(code:code);code="" } }.buttonStyle(ActionButtonStyle()).disabled(code.count != 6 || paper.busy)
                        Text("Eşleşme kodu sunucuda oluşturulur ve 3 dakika geçerlidir. Veri servisi anahtarları sunucuda tutulur.").font(.caption).foregroundStyle(.secondary)
                    }
                    if paper.snapshot != nil {
                        Card {
                            Label("İşlem sınırları",systemImage:"shield.lefthalf.filled").font(.headline)
                            Stepper("Hisse sınırı: %\(positionLimit)",value:$positionLimit,in:1...30)
                            Stepper("Günlük kayıp: %\(dailyLoss)",value:$dailyLoss,in:1...10)
                            Stepper("Komisyon: \(commission) baz puan",value:$commission,in:0...100)
                            Stepper("Fiyat kayması: \(slippage) baz puan",value:$slippage,in:0...100)
                            Text("100 baz puan = %1. Bunlar sanal gerçekleşme varsayımlarıdır. Masraf ayarını değiştirmek için bekleyen emir olmamalı.").font(.caption).foregroundStyle(.secondary)
                            Button("Sınırları kaydet") { Task {_ = await paper.mutate("settings",method:"PATCH",values:["maxPositionPercent":positionLimit,"maxDailyLossPercent":dailyLoss,"commissionBps":commission,"slippageBps":slippage])} }.buttonStyle(ActionButtonStyle(prominent:false)).disabled(!paper.canAct)
                        }
                    }
                    Card {
                        Label("Bildirimler",systemImage:"bell").font(.headline)
                        Text(paper.notificationStatus).font(.subheadline).foregroundStyle(.secondary)
                        Button("Bildirim iznini ayarla") {Task {await paper.requestNotifications()}}.frame(minHeight:44)
                        Text("İncelemeler her zaman Asistan’da saklanır. Uygulama kapalıyken bildirim için sunucunun Apple bildirim bağlantısı da açık olmalı.").font(.caption).foregroundStyle(.secondary)
                    }
                    Card {
                        Label("Görünüm",systemImage:"circle.lefthalf.filled").font(.headline)
                        Picker("Görünüm",selection:Binding(get:{legacy.preferences.appearance},set:legacy.setAppearance)) {ForEach(Appearance.allCases,id:\.self) {Text($0.title).tag($0)}}.pickerStyle(.segmented)
                        Toggle("Bakiyelerimi gizle",isOn:Binding(get:{legacy.preferences.hidesBalances},set:{_ in legacy.toggleBalances()}))
                    }
                    Card {
                        Label("Hesap yedekleri",systemImage:"externaldrive").font(.headline)
                        Button("Sanal hesabı dışa aktar") {Task {do {document=BackupDocument(data:try await paper.backup());exporting=true}catch{paper.error=error.localizedDescription}}}.disabled(!paper.canAct).frame(minHeight:44)
                        Button("Eski deneme hesabını dışa aktar") {do {document=BackupDocument(data:try legacy.exportData());exporting=true}catch{paper.error=error.localizedDescription}}.frame(minHeight:44)
                        Text("Eski örnek hesabın korunur. Yeni hesap sunucudadır; dışa aktarılan dosya şifreli değildir.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }.background(Palette.background).navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("Bitti") {dismiss()}}}
                .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"Borsa-hesap-yedegi") {result in if case .failure(let error)=result {paper.error=error.localizedDescription}}
                .onAppear {if let s=paper.snapshot?.settings {positionLimit=s.maxPositionPercent;dailyLoss=s.maxDailyLossPercent;commission=s.commissionBps;slippage=s.slippageBps}}
                .task {await paper.refreshNotificationStatus()}
        }
    }
}
