import XCTest

@MainActor
final class BorsaUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchAccount(reset: Bool = true, extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        // The test account uses a separate directory and UserDefaults suite.
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-test-state"] : []) + extra
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, searchingUp: Bool = false) {
        // SwiftUI may omit off-screen controls from the accessibility tree.
        // Scroll them into view before requiring existence or hittability.
        for _ in 0..<8 {
            if element.exists {
                let frame = element.frame
                let visibleTop = app.frame.minY + 132
                let visibleBottom = app.frame.maxY - 140
                if element.isHittable && frame.midY > visibleTop && frame.midY < visibleBottom { return }
                if frame.midY < visibleTop { app.swipeDown() } else { app.swipeUp() }
            } else if searchingUp {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Element not reachable: \(element)\n\(app.debugDescription)")
    }

    private func selectTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        tab.tapReady()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, "Tab not selected: \(title)\n\(app.debugDescription)")
    }

    private func openTHYAO() {
        let detail = app.buttons["featured-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        reveal(detail)
        detail.tapReady()
        XCTAssertTrue(app.buttons["demo-buy"].waitForExistence(timeout: 15))
    }

    private func replace(_ field: XCUIElement, with value: String) {
        reveal(field, searchingUp: true)
        field.tapReady()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        app.buttons["Bitti"].tapReady()
    }

    private func confirmOrder() {
        app.buttons["review-order"].tapReady()
        let confirm = app.buttons["confirm-demo-order"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        confirm.tapReady()
        XCTAssertTrue(app.staticTexts["order-success"].waitForExistence(timeout: 15))
        app.buttons["close-receipt"].tapReady()
    }

    func testBuyReviewConfirmationAndPersistence() {
        launchAccount()
        capture("01-market-dark")
        openTHYAO()
        capture("02-stock-detail")
        app.buttons["demo-buy"].tapReady()
        XCTAssertTrue(app.buttons["review-order"].waitForExistence(timeout: 15))
        capture("03-order-ticket")
        app.buttons["review-order"].tapReady()
        let confirm = app.buttons["confirm-demo-order"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["order-success"].exists)
        capture("04-order-review")
        confirm.tapReady()
        XCTAssertTrue(app.staticTexts["order-success"].waitForExistence(timeout: 15))
        capture("05-order-result")
        app.buttons["close-receipt"].tapReady()
        selectTab("Portföy")
        capture("06-portfolio")
        let holding = app.buttons["holding-THYAO"]
        reveal(holding)
        XCTAssertTrue(holding.label.contains("41 adet"), holding.label)
        app.terminate()
        launchAccount(reset: false)
        selectTab("Portföy")
        reveal(app.buttons["holding-THYAO"])
        XCTAssertTrue(app.buttons["holding-THYAO"].label.contains("41 adet"))
        selectTab("Emirler")
        XCTAssertTrue(app.staticTexts["Gerçekleşti"].waitForExistence(timeout: 15))
    }

    func testPendingOrderCancellationFiltersAndReleaseOfCash() {
        launchAccount()
        openTHYAO()
        app.buttons["demo-buy"].tapReady()
        replace(app.textFields["order-price"], with: "300.00")
        confirmOrder()
        selectTab("Emirler")
        app.segmentedControls["order-filter"].buttons["Bekleyen"].tapReady()
        capture("07-pending-order")
        let cancel = app.buttons["cancel-order"]
        reveal(cancel)
        cancel.tapReady()
        app.alerts.buttons["Emri iptal et"].tapReady()
        XCTAssertTrue(app.staticTexts["Bu listede emir yok"].waitForExistence(timeout: 15))
        app.segmentedControls["order-filter"].buttons["İptal"].tapReady()
        XCTAssertTrue(app.staticTexts["İptal edildi"].waitForExistence(timeout: 15))
        selectTab("Portföy")
        XCTAssertTrue(app.staticTexts[MoneyText.initialCash].exists)
    }

    func testSellValidationAndReviewEditingPreserveSide() {
        launchAccount()
        openTHYAO()
        app.buttons["demo-sell"].tapReady()
        XCTAssertTrue(app.buttons["review-order"].waitForExistence(timeout: 15))
        app.buttons["quantity-100"].tapReady()
        XCTAssertEqual(app.textFields["order-quantity"].value as? String, "40")
        replace(app.textFields["order-quantity"], with: "41")
        app.buttons["review-order"].tapReady()
        reveal(app.otherElements["order-error"].firstMatch.exists ? app.otherElements["order-error"].firstMatch : app.staticTexts["order-error"])
        XCTAssertFalse(app.buttons["confirm-demo-order"].exists)
        replace(app.textFields["order-quantity"], with: "10")
        app.buttons["review-order"].tapReady()
        XCTAssertTrue(app.buttons["confirm-demo-order"].waitForExistence(timeout: 15))
        app.buttons["Düzenle"].tapReady()
        XCTAssertTrue(app.segmentedControls["order-side"].buttons["Satış"].isSelected)
        XCTAssertEqual(app.textFields["order-quantity"].value as? String, "10")
        confirmOrder()
        selectTab("Portföy")
        reveal(app.buttons["holding-THYAO"])
        XCTAssertTrue(app.buttons["holding-THYAO"].label.contains("30 adet"))
    }

    func testSearchWatchlistAndThemePersist() {
        launchAccount()
        let search = app.textFields["market-search"]
        search.tapReady()
        search.typeText("sise")
        XCTAssertTrue(app.buttons["stock-SISE"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["stock-THYAO"].exists)
        app.buttons["stock-SISE"].tapReady()
        app.buttons["toggle-watch"].tapReady()
        selectTab("Takip")
        reveal(app.buttons["stock-SISE"])
        app.buttons["open-settings"].tapReady()
        XCTAssertTrue(app.segmentedControls["appearance-picker"].waitForExistence(timeout: 15))
        app.segmentedControls["appearance-picker"].buttons["Açık"].tapReady()
        capture("08-settings-light")
        app.navigationBars.buttons["Bitti"].tapReady()
        capture("09-watchlist-light")
        app.terminate()
        launchAccount(reset: false)
        app.buttons["open-settings"].tapReady()
        XCTAssertTrue(app.segmentedControls["appearance-picker"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls["appearance-picker"].buttons["Açık"].isSelected)
        reveal(app.staticTexts["connection-state"])
        XCTAssertTrue(app.staticTexts["connection-state"].label.contains("Gerçek emir gönderilmez"))
    }

    func testHiddenBalancesPersistAndBackupExporterOpens() {
        launchAccount()
        selectTab("Portföy")
        app.buttons["balance-visibility"].tapReady()
        XCTAssertEqual(app.staticTexts["total-balance"].label, "••••••")
        capture("10-balances-hidden")
        app.terminate()
        launchAccount(reset: false)
        selectTab("Portföy")
        XCTAssertEqual(app.staticTexts["total-balance"].label, "••••••")
        selectTab("Piyasa")
        app.buttons["open-settings"].tapReady()
        reveal(app.buttons["export-backup"])
        app.buttons["export-backup"].tapReady()
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Kaydet", "Save", "Export", "Dışa Aktar", "Taşı"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        capture("11-backup-export")
    }

    func testDamagedTestAccountRequiresExplicitRecovery() {
        launchAccount(extra: ["--corrupt-test-state"])
        XCTAssertTrue(app.staticTexts["Kaydını koruyalım."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["Piyasa"].exists)
        capture("14-record-recovery")
        reveal(app.buttons["recovery-new-account"])
        app.buttons["recovery-new-account"].tapReady()
        app.buttons["Yeni hesap oluştur"].tapReady()
        XCTAssertTrue(app.buttons["featured-detail"].waitForExistence(timeout: 15))
    }

    func testLargeTextMainScreensRemainNavigable() {
        launchAccount(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        openTHYAO()
        XCTAssertTrue(app.buttons["demo-buy"].isHittable)
        capture("12-large-text-detail")
        app.buttons["demo-buy"].tapReady()
        XCTAssertTrue(app.buttons["review-order"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["review-order"].isHittable)
        capture("13-large-text-ticket")
    }
}

private enum MoneyText {
    static let initialCash = "₺100.000,00"
}

@MainActor
private extension XCUIElement {
    func tapReady() {
        XCTAssertTrue(waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: self)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        press(forDuration: 0.12)
    }
}
