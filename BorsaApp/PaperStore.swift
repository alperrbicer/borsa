import SwiftUI
import Combine
import Security
import CryptoKit
import UserNotifications

struct ServerConnection: Codable, Sendable { let url: String, pin: String, token: String }
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
enum PaperClientError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}
private final class PinnedSession: NSObject, URLSessionDelegate, @unchecked Sendable {
    let pin: String
    init(pin: String) { self.pin = pin.lowercased().replacingOccurrences(of: ":", with: "") }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard !pin.isEmpty else { completionHandler(.performDefaultHandling,nil); return }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = certificates.first else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        let data = SecCertificateCopyData(certificate) as Data
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == pin else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust,nil) else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
private struct PaperAPI: Sendable {
    let connection: ServerConnection
    func data(_ path: String, method: String = "GET", body: Data? = nil, authenticate: Bool = true) async throws -> Data {
        guard let base = URL(string: connection.url), base.scheme == "https", base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw PaperClientError.message("Geçerli bir HTTPS sunucu adresi gir.") }
        let delegate = PinnedSession(pin: connection.pin)
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: base.appendingPathComponent(path)); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticate { request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.data(for: request)
        guard bytes.count <= 5 * 1024 * 1024 else { throw PaperClientError.message("Sunucu yanıtı çok büyük.") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode(APIError.self, from: bytes))?.error ?? "Sunucu isteği tamamlanamadı."
            throw PaperClientError.message(error)
        }
        return bytes
    }
    private struct APIError: Decodable { let error: String }
}
@MainActor
final class PaperStore: ObservableObject {
    @Published private(set) var snapshot: PaperSnapshot?
    @Published private(set) var connected = false
    @Published private(set) var connectionMessage: String?
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var selectedTab = 0
    @Published var serverURL: String
    @Published var serverPin: String
    @Published var notificationStatus = "Bildirim izni verilmedi"
    private var connection: ServerConnection?
    private var refreshing = false
    private var knownReviews: Set<String>
    private let cacheURL: URL
    private let testing: Bool
    var configured: Bool { connection != nil }
    var canAct: Bool { connected && !busy && snapshot.map { Date().timeIntervalSince1970 * 1000 - $0.serverTime < 45_000 } == true }
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
            try ConnectionVault.save(saved); connection = saved; error = nil
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let connection, !refreshing, !testing else { return }
        refreshing = true; defer { refreshing = false }
        do {
            let data = try await PaperAPI(connection: connection).data("snapshot")
            try await accept(data)
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus == .authorized ? "Bildirim izni açık" : "Bildirim izni kapalı"
            if settings.authorizationStatus == .authorized { UIApplication.shared.registerForRemoteNotifications() }
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
        do { let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]); notificationStatus = allowed ? "Bildirim izni açık" : "Bildirim izni kapalı"; if allowed { UIApplication.shared.registerForRemoteNotifications() } }
        catch { self.error = error.localizedDescription }
    }
    func registerPush() async {
        guard let connection, let token = UserDefaults.standard.string(forKey: "borsa.push.token"), !testing else { return }
        _ = try? await PaperAPI(connection: connection).data("device", method: "POST", body: JSONSerialization.data(withJSONObject: ["token":token]))
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
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { UserDefaults.standard.set(deviceToken.map { String(format: "%02x", $0) }.joined(),forKey: "borsa.push.token") }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner,.sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor in NotificationCenter.default.post(name: .init("BorsaOpenReviews"),object:nil) }; completionHandler()
    }
}
