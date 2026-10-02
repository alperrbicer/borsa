import Foundation
import Security
import CryptoKit

struct ServerConnection: Codable, Sendable { let url: String, pin: String, token: String }
enum PaperClientError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}
private final class PinnedSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        urlSession(session,didReceive:challenge,completionHandler:completionHandler)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
struct PaperAPI: Sendable {
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
        let (stream, response) = try await session.bytes(for: request)
        let limit = (path == "backup" ? 64 : 5) * 1024 * 1024
        guard response.expectedContentLength <= limit else { session.invalidateAndCancel(); throw PaperClientError.message("Sunucu yanıtı çok büyük.") }
        var bytes = Data()
        for try await byte in stream {
            guard bytes.count < limit else { session.invalidateAndCancel(); throw PaperClientError.message("Sunucu yanıtı çok büyük.") }
            bytes.append(byte)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode(APIError.self, from: bytes))?.error ?? "Sunucu isteği tamamlanamadı."
            throw PaperClientError.message(error)
        }
        return bytes
    }
    private struct APIError: Decodable { let error: String }
}
