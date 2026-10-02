import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw SnapshotError.unreadable }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PreferencesView: View {
    var recoveryMode = false
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var incoming: AppSnapshot?
    @State private var confirmImport = false
    @State private var confirmPrevious = false
    @State private var confirmNewAccount = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: recoveryMode ? "externaldrive.badge.exclamationmark" : "person.crop.square")
                            .font(.largeTitle).foregroundStyle(Palette.accent)
                        Text(recoveryMode ? "Kaydını koruyalım." : "Sana göre Borsa.").font(.largeTitle.weight(.semibold))
                        Text(recoveryMode ? "Hesap kaydı okunamadığı için işlemler durduruldu. Mevcut dosyan silinmedi. Geçerli bir yedekten devam edebilirsin." : "Görünümünü seç, verinin kontrolünü elinde tut.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    if !recoveryMode {
                        Card {
                            Label("Görünüm", systemImage: "circle.lefthalf.filled").font(.headline)
                            Picker("Görünüm", selection: Binding(get: { store.preferences.appearance }, set: store.setAppearance)) {
                                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).accessibilityIdentifier("appearance-picker")
                            Toggle("Bakiyelerimi gizle", isOn: Binding(get: { store.preferences.hidesBalances }, set: { _ in store.toggleBalances() }))
                                .font(.subheadline).accessibilityIdentifier("hide-balances")
                        }
                    }
                    Card {
                        Label("Verilerin", systemImage: "externaldrive").font(.headline)
                        Text("Hesabın bu cihazda saklanır. Dışa aktardığın yedeği Dosyalar’a kaydedip daha sonra geri yükleyebilirsin.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !recoveryMode {
                            Button {
                                do { exportDocument = BackupDocument(data: try store.exportData()); exporting = true }
                                catch { message = error.localizedDescription }
                            } label: { Label("Yedeği dışa aktar", systemImage: "square.and.arrow.up") }
                                .buttonStyle(ActionButtonStyle()).accessibilityIdentifier("export-backup")
                        }
                        Button { importing = true } label: { Label("Yedekten geri yükle", systemImage: "square.and.arrow.down") }
                            .buttonStyle(ActionButtonStyle(prominent: false)).accessibilityIdentifier("import-backup")
                        if store.hasBackup {
                            Button("Bir önceki yerel kaydı geri al") { confirmPrevious = true }
                                .font(.subheadline).padding(.vertical, 7)
                        }
                        Text("Uygulamayı silmek yerel kayıtları da silebilir. Otomatik bulut eşitlemesi yoktur.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if recoveryMode {
                        Button("Yeni deneme hesabı oluştur") { confirmNewAccount = true }
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("recovery-new-account")
                    }
                    if !recoveryMode {
                        Card {
                            Label("Hesap ve veri kaynağı", systemImage: "building.columns").font(.headline)
                            InfoRow(title: "Hesap", value: "Deneme hesabı")
                            InfoRow(title: "Fiyat kaynağı", value: "Sabit örnek veri")
                            InfoRow(title: "Aracı kurum", value: "Bağlı değil")
                            Text("Gerçek emir gönderilmez. Fiyatlar, grafikler ve başlangıç varlıkları temsili veridir. Gerçek alım satım için kurum bağlantısı gerekir.")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("connection-state")
                        }
                    }
                    Text("Borsa · Kişisel çalışma alanın").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(20)
            }
            .background(Palette.background)
            .navigationTitle(recoveryMode ? "Kayıt kurtarma" : "Ayarlar").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !recoveryMode { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                          defaultFilename: "Borsa-yedek-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= AppSnapshot.maximumBytes else { throw SnapshotError.oversized }
                    incoming = try AppSnapshot.decode(Data(contentsOf: url))
                    confirmImport = true
                } catch { message = error.localizedDescription }
            }
            .confirmationDialog("Hesap yedekten geri yüklensin mi?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Geri yükle") {
                    guard let incoming else { return }
                    do { try store.restore(incoming); self.incoming = nil; message = "Yedek geri yüklendi." }
                    catch { message = error.localizedDescription }
                }
                Button("Vazgeç", role: .cancel) { incoming = nil }
            } message: {
                if let incoming {
                    Text("\(incoming.account.positions.count) varlık, \(incoming.account.orders.count) emir ve \(incoming.watchlist.count) takip kaydı içeren bu dosya mevcut hesabın yerini alacak. Mevcut kayıt yerel kopya olarak korunacak.")
                }
            }
            .confirmationDialog("Bir önceki kayda dönülsün mü?", isPresented: $confirmPrevious, titleVisibility: .visible) {
                Button("Önceki kaydı geri yükle") {
                    do { try store.restorePrevious(); message = "Önceki kayıt geri yüklendi." }
                    catch { message = error.localizedDescription }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { Text("Son kayıttan sonraki değişikliklerin yerini önceki kayıt alacak. Mevcut dosya korunacak.") }
            .confirmationDialog("Yeni deneme hesabı oluşturulsun mu?", isPresented: $confirmNewAccount, titleVisibility: .visible) {
                Button("Yeni hesap oluştur") {
                    do { try store.restore(AppSnapshot()) }
                    catch { message = error.localizedDescription }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { Text("Başlangıç bakiyesi ve örnek varlıklarla yeniden başlayacaksın. Okunamayan eski dosya cihazda korunur; eski işlemler yeni hesaba taşınmaz.") }
            .alert("Hesap kaydı", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Tamam") { message = nil }
            } message: { Text(message ?? "") }
        }.preferredColorScheme(store.preferredColorScheme)
    }
}
