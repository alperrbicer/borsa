import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot = AppSnapshot()
    @Published private(set) var recoveryRequired = false
    @Published var storageMessage: String?
    private let storage: FileSnapshotStorage
    private var transaction: SnapshotTransaction?

    var account: DemoAccount { snapshot.account }
    var watchlist: Set<String> { snapshot.watchlist }
    var preferences: Preferences { snapshot.preferences }
    var hasBackup: Bool { (try? storage.readBackup()) != nil }
    var preferredColorScheme: ColorScheme? {
        switch preferences.appearance { case .dark: .dark; case .light: .light; case .system: nil }
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        let testing = arguments.contains("--ui-testing")
        #else
        let testing = false
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(testing ? "BorsaUITestAccount" : "BorsaAccount", isDirectory: true)
        storage = FileSnapshotStorage(directory: directory)
        let defaults = testing ? UserDefaults(suiteName: "borsa.ui.tests")! : .standard
        if testing && arguments.contains("--reset-test-state") {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: "borsa.ui.tests")
        }
        #if DEBUG
        if testing && arguments.contains("--corrupt-test-state") {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data("interrupted-test-write".utf8).write(to: storage.primaryURL, options: .atomic)
        }
        #endif
        do {
            let loaded: AppSnapshot
            if let existing = try storage.load() {
                loaded = existing
            } else if let legacy = defaults.data(forKey: "borsa.demo.snapshot.v1") {
                loaded = try AppSnapshot.decode(legacy)
                try storage.save(loaded)
                // The old key is retained as a migration fallback; it is never rewritten.
            } else {
                loaded = AppSnapshot()
                try storage.save(loaded)
            }
            snapshot = loaded
            transaction = SnapshotTransaction(value: loaded, storage: storage)
        } catch {
            recoveryRequired = true
            storageMessage = error.localizedDescription
        }
    }

    private func update(_ change: (inout AppSnapshot) throws -> Void) throws {
        guard !recoveryRequired, var next = transaction else { throw SnapshotError.unreadable }
        try next.update(change)
        transaction = next
        snapshot = next.value
    }

    func toggleWatch(_ symbol: String) {
        do {
            try update { value in
                if value.watchlist.contains(symbol) { value.watchlist.remove(symbol) }
                else { value.watchlist.insert(symbol) }
            }
        } catch { storageMessage = error.localizedDescription }
    }

    func setAppearance(_ appearance: Appearance) {
        do { try update { $0.preferences.appearance = appearance } }
        catch { storageMessage = error.localizedDescription }
    }

    func toggleBalances() {
        do { try update { $0.preferences.hidesBalances.toggle() } }
        catch { storageMessage = error.localizedDescription }
    }

    func money(_ amount: Int64) -> String { preferences.hidesBalances ? "••••••" : Money.formatted(amount) }

    func submit(_ request: OrderRequest) throws -> Order {
        var result: Order?
        try update { result = try $0.account.submit(request) }
        guard let result else { throw SnapshotError.writeFailed }
        return result
    }

    func cancel(_ order: Order) throws { try update { try $0.account.cancel(order.id) } }
    func exportData() throws -> Data { guard !recoveryRequired else { throw SnapshotError.unreadable }; return try snapshot.encoded() }

    func restore(_ incoming: AppSnapshot) throws {
        try incoming.validate()
        try storage.restore(incoming)
        snapshot = incoming
        transaction = SnapshotTransaction(value: incoming, storage: storage)
        recoveryRequired = false
        storageMessage = nil
    }

    func restorePrevious() throws { try restore(storage.readBackup()) }
}
