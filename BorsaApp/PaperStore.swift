import SwiftUI
import Combine
import Security
import UserNotifications

private enum ConnectionVault {
    static let service = "dev.prototype.borsa.server"
    static func read() -> ServerConnection? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"primary",kSecReturnData as String:true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ServerConnection.self, from: data)
    }
    static func save(_ connection: ServerConnection) throws {
        let data = try JSONEncoder().encode(connection)
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"primary"]
        let status = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary,nil) == errSecSuccess else { throw PaperClientError.message("Bağlantı bilgisi güvenli alana kaydedilemedi.") }; return
        }
        guard status == errSecSuccess else { throw PaperClientError.message("Bağlantı bilgisi güncellenemedi.") }
    }
}
@MainActor
final class PaperStore: ObservableObject {
    @Published private(set) var snapshot: PaperSnapshot?
    @Published private(set) var connected = false
    @Published private(set) var connectionMessage: String?
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var selectedTab = 0
    @Published var requestedReviewID: String?
    @Published var serverURL: String
    @Published var serverPin: String
    @Published var notificationStatus = "Bildirim izni verilmedi"
    private var connection: ServerConnection?
    private var refreshing = false
    private var registeredToken: String?
    private var knownReviews: Set<String>
    private let cacheURL: URL
    private let testing: Bool
    var configured: Bool { connection != nil }
    var canAct: Bool { connected && !busy && snapshot.map { let age = Date().timeIntervalSince1970 * 1000 - $0.serverTime; return age >= -2000 && age < 45_000 } == true }
    init() {
        #if DEBUG
        testing = ProcessInfo.processInfo.arguments.contains("--paper-ui-testing")
        #else
        testing = false
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = base.appendingPathComponent(testing ? "BorsaPaperUITestCache.json" : "BorsaPaperCache.json")
        connection = testing ? nil : ConnectionVault.read()
        let host = Bundle.main.object(forInfoDictionaryKey: "BorsaServerHost") as? String ?? ""
        serverURL = connection?.url ?? (host.isEmpty ? "" : "https://\(host):8787")
        serverPin = connection?.pin ?? (Bundle.main.object(forInfoDictionaryKey: "BorsaServerPin") as? String ?? "")
        knownReviews = Set(testing ? [] : UserDefaults.standard.stringArray(forKey: "borsa.paper.seenReviews") ?? [])
        if !testing, let data = try? Data(contentsOf: cacheURL), data.count <= 5 * 1024 * 1024 { snapshot = try? JSONDecoder().decode(PaperSnapshot.self, from: data) }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if !testing, let index = args.firstIndex(of: "--pair-code"), args.indices.contains(index+1) { let code = args[index+1]; Task { await pair(code: code) } }
        #endif
    }
    func pair(code: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let candidate = ServerConnection(url: serverURL.trimmingCharacters(in: .whitespacesAndNewlines), pin: serverPin.trimmingCharacters(in: .whitespacesAndNewlines), token: "")
            if !candidate.pin.isEmpty && candidate.pin.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) == nil { throw PaperClientError.message("Sertifika parmak izi 64 onaltılık karakter olmalı.") }
            struct Pair: Decodable { let token: String }
            let data = try await PaperAPI(connection: candidate).data("pair", method: "POST", body: JSONSerialization.data(withJSONObject: ["code":code]), authenticate: false)
            let token = try JSONDecoder().decode(Pair.self, from: data).token
            let saved = ServerConnection(url: candidate.url,pin:candidate.pin,token:token)
            try ConnectionVault.save(saved); connection = saved; registeredToken = nil; error = nil
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let connection, !refreshing, !testing else { return }
        refreshing = true; defer { refreshing = false }
        do {
            let data = try await PaperAPI(connection: connection).data("snapshot")
            try await accept(data)
            await refreshNotificationStatus()
            await registerPush()
        }
        catch { connected = false; connectionMessage = error.localizedDescription }
    }
    private func accept(_ data: Data) async throws {
        let value = try JSONDecoder().decode(PaperSnapshot.self, from: data)
        guard value.version == 1 else { throw PaperClientError.message("Sunucu sürümü uygulamayla uyumlu değil.") }
        if let previous = snapshot, previous.createdAt == value.createdAt, previous.revision > value.revision { return }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        snapshot = value; connected = true; connectionMessage = nil
        let remoteDelivery = value.health.first { $0.id == "notifications" }.map { $0.status == "connected" || $0.status == "ready" } ?? false
        for review in value.reviews where !remoteDelivery && !knownReviews.contains(review.id) {
            let content = UNMutableNotificationContent(); content.title = "\(review.symbol) için inceleme"; content.body = "Kararını kaynaklarıyla birlikte inceleyebilirsin."; content.userInfo = ["decisionId":review.id]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: review.id, content: content, trigger: nil))
        }
        knownReviews.formUnion(value.decisions.map(\.id))
        if knownReviews.count > 2500 { knownReviews = Set(value.decisions.map(\.id)) }
        UserDefaults.standard.set(Array(knownReviews), forKey: "borsa.paper.seenReviews")
    }
    func mutate(_ path: String, method: String = "POST", values: [String: Any] = [:]) async -> Bool {
        guard let connection, canAct else { error = "Önce sunucuyla güncel bağlantı kurulmalı."; return false }
        busy = true; defer { busy = false }
        do {
            let data = try await PaperAPI(connection: connection).data(path,method:method,body:JSONSerialization.data(withJSONObject: values))
            try await accept(data); return true
        }
        catch { self.error = error.localizedDescription; return false }
    }
    func requestNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied, let url = URL(string:UIApplication.openSettingsURLString) { await UIApplication.shared.open(url); return }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]); await refreshNotificationStatus() }
        catch { self.error = error.localizedDescription }
    }
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed = [.authorized,.provisional,.ephemeral].contains(settings.authorizationStatus)
        notificationStatus = allowed ? "Bildirim izni açık" : "Bildirim izni kapalı"
        if allowed {
            if let failure = UserDefaults.standard.string(forKey:"borsa.push.error") { notificationStatus = failure }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    func registerPush() async {
        guard let connection, let token = UserDefaults.standard.string(forKey: "borsa.push.token"), !testing else { return }
        let key = connection.token + token
        guard registeredToken != key else { return }
        do {
            _ = try await PaperAPI(connection: connection).data("device", method: "POST", body: JSONSerialization.data(withJSONObject: ["token":token]))
            registeredToken = key
        } catch { notificationStatus = "Bildirim izni açık; sunucuya cihaz kaydı iletilemedi." }
    }
    func openPendingReview() {
        guard !testing, let id = UserDefaults.standard.string(forKey:"borsa.paper.pendingReview") else { return }
        UserDefaults.standard.removeObject(forKey:"borsa.paper.pendingReview")
        requestedReviewID = id; selectedTab = 3
    }
    func backup() async throws -> Data {
        guard let connection else { throw PaperClientError.message("Sunucu bağlantısı gerekli.") }
        return try await PaperAPI(connection: connection).data("backup")
    }
    func preview(decisionID: String, side: String) async -> PaperPreview? {
        guard let connection, canAct else { return nil }
        busy = true; defer { busy = false }
        do {
            let data = try await PaperAPI(connection: connection).data("decisions/\(decisionID)/preview",method:"POST",body:JSONSerialization.data(withJSONObject:["choice":side]))
            return try JSONDecoder().decode(PaperPreview.self,from:data)
        } catch { self.error = error.localizedDescription; return nil }
    }
}
final class BorsaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { UNUserNotificationCenter.current().delegate = self; return true }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        UserDefaults.standard.set(deviceToken.map { String(format: "%02x", $0) }.joined(),forKey: "borsa.push.token")
        UserDefaults.standard.removeObject(forKey:"borsa.push.error")
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { UserDefaults.standard.set("Apple bildirim kaydı alınamadı; bağlantını kontrol et.",forKey:"borsa.push.error") }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner,.sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let id = response.notification.request.content.userInfo["decisionId"] as? String
        Task { @MainActor in
            if let id, id.count <= 80 { UserDefaults.standard.set(id,forKey:"borsa.paper.pendingReview") }
            NotificationCenter.default.post(name: .init("BorsaOpenReviews"),object:nil)
        }; completionHandler()
    }
}
