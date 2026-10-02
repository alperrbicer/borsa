import Foundation

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case dark, light, system
    public var title: String { switch self { case .dark: "Koyu"; case .light: "Açık"; case .system: "Sistem" } }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: Appearance = .dark
    public var hidesBalances = false
    public init() {}
}

public enum SnapshotError: Error, LocalizedError, Equatable {
    case unreadable, unsupportedVersion, oversized, invalidWatchlist, writeFailed
    public var errorDescription: String? {
        switch self {
        case .unreadable: "Hesap kaydı okunamadı. Mevcut kayıt korunuyor. Bir yedekten geri yükleyebilirsin."
        case .unsupportedVersion: "Bu yedek, bu sürümün desteklemediği bir biçimde. Hesabın değiştirilmedi."
        case .oversized: "Yedek dosyası 5 MB sınırını aşıyor. Hesabın değiştirilmedi."
        case .invalidWatchlist: "Yedekte geçersiz bir takip listesi var. Hesabın değiştirilmedi."
        case .writeFailed: "İşlem kaydedilemedi; hesabın değiştirilmedi. Cihazın boş alanını kontrol edip tekrar dene."
        }
    }
}

public struct AppSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public var account: DemoAccount
    public var watchlist: Set<String>
    public var preferences: Preferences
    public static let maximumBytes = 5 * 1024 * 1024

    public init(account: DemoAccount = DemoAccount(), watchlist: Set<String> = ["THYAO", "ASELS", "TUPRS"], preferences: Preferences = Preferences()) {
        version = 2
        self.account = account; self.watchlist = watchlist; self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey { case version, account, watchlist, preferences }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceVersion = try container.decode(Int.self, forKey: .version)
        guard sourceVersion == 1 || sourceVersion == 2 else { throw SnapshotError.unsupportedVersion }
        version = 2
        account = try container.decode(DemoAccount.self, forKey: .account)
        watchlist = try container.decode(Set<String>.self, forKey: .watchlist)
        preferences = try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        try validate()
    }

    public func validate() throws {
        try account.validateState()
        guard watchlist.isSubset(of: Set(DemoMarket.instruments.map(\.symbol))) else { throw SnapshotError.invalidWatchlist }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw SnapshotError.oversized }
        return data
    }

    public static func decode(_ data: Data) throws -> AppSnapshot {
        guard data.count <= maximumBytes else { throw SnapshotError.oversized }
        do { return try JSONDecoder().decode(AppSnapshot.self, from: data) }
        catch let error as SnapshotError { throw error }
        catch { throw SnapshotError.unreadable }
    }
}

public protocol SnapshotStorage {
    func load() throws -> AppSnapshot?
    func save(_ snapshot: AppSnapshot) throws
}

/// Publishes in-memory state only after its complete snapshot is written.
public struct SnapshotTransaction {
    public private(set) var value: AppSnapshot
    private let storage: any SnapshotStorage
    public init(value: AppSnapshot, storage: any SnapshotStorage) { self.value = value; self.storage = storage }
    public mutating func update(_ change: (inout AppSnapshot) throws -> Void) throws {
        var candidate = value
        try change(&candidate)
        try candidate.validate()
        guard candidate != value else { return }
        do { try storage.save(candidate) }
        catch { throw SnapshotError.writeFailed }
        value = candidate
    }
}

public struct FileSnapshotStorage: SnapshotStorage {
    public let directory: URL
    public var primaryURL: URL { directory.appendingPathComponent("account.json") }
    public var backupURL: URL { directory.appendingPathComponent("account.previous.json") }
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            if FileManager.default.fileExists(atPath: backupURL.path) { throw SnapshotError.unreadable }
            return nil
        }
        return try read(primaryURL)
    }

    public func readBackup() throws -> AppSnapshot { try read(backupURL) }

    private func read(_ url: URL) throws -> AppSnapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= AppSnapshot.maximumBytes else { throw SnapshotError.oversized }
        return try AppSnapshot.decode(Data(contentsOf: url))
    }

    public func save(_ snapshot: AppSnapshot) throws { try write(snapshot, allowsRecovery: false) }
    /// Only used after the user confirms importing/restoring a checked backup.
    public func restore(_ snapshot: AppSnapshot) throws { try write(snapshot, allowsRecovery: true) }

    private func write(_ snapshot: AppSnapshot, allowsRecovery: Bool) throws {
        let data = try snapshot.encoded()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            // Never turn a damaged primary into the only backup or silently overwrite it.
            do {
                let current = try read(primaryURL)
                try current.encoded().write(to: backupURL, options: options)
            } catch {
                guard allowsRecovery else { throw error }
                let preserved = directory.appendingPathComponent("preserved-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: primaryURL, to: preserved)
            }
        }
        try data.write(to: primaryURL, options: options)
    }
}

public enum MarketSort: String, CaseIterable, Sendable {
    case symbol, gainers, losers, price
    public var title: String {
        switch self { case .symbol: "Hisse kodu"; case .gainers: "En çok yükselen"; case .losers: "En çok düşen"; case .price: "Fiyat" }
    }
}

public enum MarketQuery {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func find(_ instruments: [Instrument], query: String, sort: MarketSort) -> [Instrument] {
        let needle = normalized(query)
        return instruments.filter { needle.isEmpty || normalized("\($0.symbol) \($0.name) \($0.sector)").contains(needle) }
            .sorted {
                switch sort {
                case .symbol: return $0.symbol < $1.symbol
                case .gainers: return $0.changePercent == $1.changePercent ? $0.symbol < $1.symbol : $0.changePercent > $1.changePercent
                case .losers: return $0.changePercent == $1.changePercent ? $0.symbol < $1.symbol : $0.changePercent < $1.changePercent
                case .price: return $0.price == $1.price ? $0.symbol < $1.symbol : $0.price > $1.price
                }
            }
    }
}
