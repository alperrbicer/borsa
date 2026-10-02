import Foundation
import XCTest
@testable import BorsaCore

@MainActor
final class PaperAPITests: XCTestCase {
    private struct Endpoint: Decodable { let url: String, pin: String }
    private struct Paired: Decodable { let token: String }
    private func withServer(_ check: (ServerConnection) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("borsa-api-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cert = Process()
        cert.executableURL = URL(fileURLWithPath:"/usr/bin/openssl")
        cert.arguments = ["req","-x509","-newkey","rsa:2048","-sha256","-days","1","-nodes","-keyout",directory.appendingPathComponent("key.pem").path,"-out",directory.appendingPathComponent("cert.pem").path,"-subj","/CN=localhost","-addext","subjectAltName=DNS:localhost,IP:127.0.0.1","-addext","extendedKeyUsage=serverAuth","-addext","keyUsage=critical,digitalSignature,keyEncipherment","-addext","basicConstraints=critical,CA:FALSE"]
        cert.standardOutput = FileHandle.nullDevice; cert.standardError = FileHandle.nullDevice
        try cert.run(); cert.waitUntilExit()
        XCTAssertEqual(cert.terminationStatus,0)
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("../../").standardized
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
        process.arguments = ["bun",root.appendingPathComponent("Tests/Fixtures/https-server.mjs").path,directory.path]
        var environment = ProcessInfo.processInfo.environment; environment["BORSA_TEST_FIXTURE"] = "1"
        process.environment = environment
        let log = Pipe(); process.standardError = log; process.standardOutput = log
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let ready = directory.appendingPathComponent("ready.json")
        for _ in 0..<150 {
            if FileManager.default.fileExists(atPath:ready.path) || !process.isRunning { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        guard FileManager.default.fileExists(atPath:ready.path) else {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            XCTFail("Fixture server did not start: " + String(decoding:log.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)); return
        }
        let endpoint = try JSONDecoder().decode(Endpoint.self,from:Data(contentsOf:ready))
        try await check(ServerConnection(url:endpoint.url,pin:endpoint.pin,token:""))
    }

    func testPinnedHTTPSPairingAndActualServerSnapshotDecode() async throws {
        try await withServer { connection in
            let publicAPI = PaperAPI(connection:connection)
            let response = try await publicAPI.data("pair",method:"POST",body:JSONSerialization.data(withJSONObject:["code":"654321"]),authenticate:false)
            let paired = try JSONDecoder().decode(Paired.self,from:response)
            let api = PaperAPI(connection:ServerConnection(url:connection.url,pin:connection.pin,token:paired.token))
            let data = try await api.data("snapshot")
            let snapshot = try JSONDecoder().decode(PaperSnapshot.self,from:data)
            XCTAssertEqual(snapshot.version,1)
            XCTAssertEqual(snapshot.instruments.count,16)
            XCTAssertEqual(snapshot.wallets.map(\.currency),["TRY","USD"])
            XCTAssertEqual(snapshot.orders.first?.filledQty,2)
            XCTAssertEqual(snapshot.orders.first?.feesCents,21)
            XCTAssertEqual(snapshot.positions.first?.costCents,20_031)
            XCTAssertEqual(snapshot.news.first?.source,"TEST FIXTURE ONLY")
            XCTAssertEqual(snapshot.decisions.first?.state,"review")
            let decision = try XCTUnwrap(snapshot.decisions.first)
            // Cooldown blocks a second decision order on the same symbol after the fixture trade.
            do {
                _ = try await api.data("decisions/\(decision.id)/preview",method:"POST",body:JSONSerialization.data(withJSONObject:["choice":"buy"]))
                XCTFail("Expected the server's risk rule to reject the preview")
            } catch { XCTAssertTrue(error.localizedDescription.contains("bekleme")) }
            let backup = try await api.data("backup")
            XCTAssertFalse(backup.isEmpty)
        }
    }

    func testWrongCertificatePinFailsWithoutPairing() async throws {
        try await withServer { connection in
            let api = PaperAPI(connection:ServerConnection(url:connection.url,pin:String(repeating:"0",count:64),token:""))
            do { _ = try await api.data("health",authenticate:false); XCTFail("Incorrect certificate pin was accepted") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }

    func testUnauthenticatedRequestReturnsReadableError() async throws {
        try await withServer { connection in
            do { _ = try await PaperAPI(connection:connection).data("snapshot"); XCTFail("Missing credential was accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("eşleşmen")) }
        }
    }
    func testRedirectIsRejectedInsteadOfForwardingCredentials() async throws {
        try await withServer { connection in
            do { _ = try await PaperAPI(connection:connection).data("redirect"); XCTFail("Redirect unexpectedly followed") }
            catch { XCTAssertEqual(error.localizedDescription,"Sunucu isteği tamamlanamadı.") }
        }
    }
}
