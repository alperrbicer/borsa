import XCTest
@testable import BorsaCore

final class PersistenceTests: XCTestCase {
    private final class MemoryStorage: SnapshotStorage {
        var value: AppSnapshot?
        var failWrites = false
        var saves = 0
        func load() throws -> AppSnapshot? { value }
        func save(_ snapshot: AppSnapshot) throws {
            saves += 1
            if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
            value = snapshot
        }
    }
    private func changingJSON(_ snapshot: AppSnapshot = AppSnapshot(), _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
    private func storage() throws -> FileSnapshotStorage {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BorsaTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FileSnapshotStorage(directory: directory)
    }

    func testFailedWriteDoesNotPublishTradeOrPreferences() throws {
        let disk = MemoryStorage()
        var transaction = SnapshotTransaction(value: AppSnapshot(), storage: disk)
        let original = transaction.value
        disk.failWrites = true
        XCTAssertThrowsError(try transaction.update {
            try $0.account.submit(.init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 31_250))
            $0.preferences.hidesBalances = true
        }) { XCTAssertEqual($0 as? SnapshotError, .writeFailed) }
        XCTAssertEqual(transaction.value, original)
        XCTAssertNil(disk.value)
        disk.failWrites = false
        try transaction.update { $0.watchlist.remove("THYAO") }
        XCTAssertFalse(transaction.value.watchlist.contains("THYAO"))
        XCTAssertEqual(disk.value, transaction.value)
    }

    func testRejectedMutationDoesNotWriteAnything() throws {
        let disk = MemoryStorage()
        var transaction = SnapshotTransaction(value: AppSnapshot(), storage: disk)
        let original = transaction.value
        XCTAssertThrowsError(try transaction.update { $0.watchlist.insert("UNKNOWN") })
        XCTAssertEqual(disk.saves, 0)
        XCTAssertEqual(transaction.value, original)
    }

    func testVersionOneMigrationRecoversRealizedProfitAndKeepsAccount() throws {
        var account = DemoAccount()
        try account.submit(.init(symbol: "THYAO", side: .sell, quantity: 10, limitPrice: 31_250))
        try account.submit(.init(symbol: "ASELS", side: .buy, quantity: 3, limitPrice: 6_840))
        let before = AppSnapshot(account: account, watchlist: ["SISE"])
        let oldData = try changingJSON(before) { object in
            object["version"] = 1
            object.removeValue(forKey: "preferences")
            var oldAccount = object["account"] as! [String: Any]
            oldAccount.removeValue(forKey: "realizedProfit")
            object["account"] = oldAccount
        }
        let migrated = try AppSnapshot.decode(oldData)
        XCTAssertEqual(migrated.version, 2)
        XCTAssertEqual(migrated.account, before.account)
        XCTAssertEqual(migrated.account.realizedProfit, 24_500)
        XCTAssertEqual(migrated.watchlist, ["SISE"])
        XCTAssertEqual(migrated.preferences.appearance, .dark)
    }

    func testExportImportRoundTripPreservesReservationsAndPreferences() throws {
        var snapshot = AppSnapshot()
        try snapshot.account.submit(.init(symbol: "THYAO", side: .buy, quantity: 4, limitPrice: 30_000))
        snapshot.preferences.appearance = .light
        snapshot.preferences.hidesBalances = true
        snapshot.watchlist = []
        XCTAssertEqual(try AppSnapshot.decode(snapshot.encoded()), snapshot)
    }

    func testMalformedFutureAndOversizedSnapshotsAreRejected() throws {
        XCTAssertThrowsError(try AppSnapshot.decode(Data("broken".utf8)))
        XCTAssertThrowsError(try AppSnapshot.decode(changingJSON { $0["version"] = 99 })) {
            XCTAssertEqual($0 as? SnapshotError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try AppSnapshot.decode(changingJSON { $0["watchlist"] = ["UNKNOWN"] }))
        XCTAssertThrowsError(try AppSnapshot.decode(Data(repeating: 0, count: AppSnapshot.maximumBytes + 1))) {
            XCTAssertEqual($0 as? SnapshotError, .oversized)
        }
    }

    func testDecodedAccountRejectsOverflowAndInvalidPositionsBeforeArithmetic() throws {
        for cash in [-1, Int64.max] {
            let data = try changingJSON { root in
                var account = root["account"] as! [String: Any]
                account["cash"] = cash
                root["account"] = account
            }
            XCTAssertThrowsError(try AppSnapshot.decode(data))
        }
        for position in [
            ["symbol": "THYAO", "quantity": Int.max, "cost": 1] as [String: Any],
            ["symbol": "UNKNOWN", "quantity": 1, "cost": 1],
            ["symbol": "THYAO", "quantity": 1, "cost": -1]
        ] {
            let data = try changingJSON { root in
                var account = root["account"] as! [String: Any]
                account["positions"] = [position]
                root["account"] = account
            }
            XCTAssertThrowsError(try AppSnapshot.decode(data))
        }
    }

    func testDecodedOrdersRejectOverReservationAndDuplicateIDs() throws {
        var account = DemoAccount()
        try account.submit(.init(symbol: "THYAO", side: .buy, quantity: 1, limitPrice: 30_000))
        let original = AppSnapshot(account: account)
        let excessive = try changingJSON(original) { root in
            var object = root["account"] as! [String: Any]
            var orders = object["orders"] as! [[String: Any]]
            var request = orders[0]["request"] as! [String: Any]
            request["quantity"] = 100_000
            orders[0]["request"] = request
            object["orders"] = orders
            root["account"] = object
        }
        XCTAssertThrowsError(try AppSnapshot.decode(excessive))
        let duplicate = try changingJSON(original) { root in
            var object = root["account"] as! [String: Any]
            let orders = object["orders"] as! [[String: Any]]
            object["orders"] = orders + orders
            root["account"] = object
        }
        XCTAssertThrowsError(try AppSnapshot.decode(duplicate))
    }

    func testAtomicStorageKeepsPreviousSnapshotAndReloadsCurrent() throws {
        let disk = try storage()
        XCTAssertNil(try disk.load())
        let original = AppSnapshot()
        try disk.save(original)
        var updated = original
        updated.watchlist = ["SISE"]
        try disk.save(updated)
        XCTAssertEqual(try disk.load(), updated)
        XCTAssertEqual(try disk.readBackup(), original)
    }

    func testDamagedPrimaryIsNeverSilentlyOverwrittenAndCanBeRecovered() throws {
        let disk = try storage()
        let original = AppSnapshot()
        try disk.save(original)
        var second = original
        second.preferences.appearance = .light
        try disk.save(second)
        let corrupt = Data("truncated-account".utf8)
        try corrupt.write(to: disk.primaryURL)
        XCTAssertThrowsError(try disk.load())
        XCTAssertThrowsError(try disk.save(second))
        XCTAssertEqual(try Data(contentsOf: disk.primaryURL), corrupt)
        XCTAssertEqual(try disk.readBackup(), original)
        try disk.restore(disk.readBackup())
        XCTAssertEqual(try disk.load(), original)
        let preserved = try FileManager.default.contentsOfDirectory(at: disk.directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("preserved-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved.first)), corrupt)
    }

    func testMissingPrimaryWithBackupRequiresRecoveryInsteadOfNewAccount() throws {
        let disk = try storage()
        try disk.save(AppSnapshot())
        try disk.save(AppSnapshot())
        try FileManager.default.removeItem(at: disk.primaryURL)
        XCTAssertThrowsError(try disk.load())
        try disk.restore(disk.readBackup())
        XCTAssertNotNil(try disk.load())
    }
}
