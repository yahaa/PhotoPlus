import XCTest

/// The whole MVP through the real UI, PhotoKit and NAS, on generated images in a dedicated album.
/// The app is confined to that album, so other photos on the device are never read or changed.
/// Needs TEST_RUNNER_PHOTOPLUS_SERVER_URL and TEST_RUNNER_PHOTOPLUS_TOKEN.
final class ArchiveFlowUITests: XCTestCase {
    private static let album = "PhotoPlus E2E Fixture"
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(count: Int? = nil, cleanup: Bool = false) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let url = try XCTUnwrap(env["PHOTOPLUS_SERVER_URL"], "set TEST_RUNNER_PHOTOPLUS_SERVER_URL")
        let token = try XCTUnwrap(env["PHOTOPLUS_TOKEN"], "set TEST_RUNNER_PHOTOPLUS_TOKEN")
        let app = XCUIApplication()
        app.launchEnvironment["PHOTOPLUS_FIXTURE_ALBUM"] = Self.album
        app.launchEnvironment["PHOTOPLUS_SERVER_URL"] = url
        app.launchEnvironment["PHOTOPLUS_TOKEN"] = token
        if let count { app.launchEnvironment["PHOTOPLUS_FIXTURE_COUNT"] = String(count) }
        if cleanup { app.launchEnvironment["PHOTOPLUS_FIXTURE_CLEANUP"] = "1" }
        app.launch()
        return app
    }

    func testArchiveFreeAndViewFromNAS() throws {
        let count = Int(ProcessInfo.processInfo.environment["PHOTOPLUS_FIXTURE_COUNT"] ?? "") ?? 4
        let app = try launch(count: count)
        // The newest quarter of fixtures sits inside the retention window; the rest are old.
        let recent = max(count / 4, 1)
        let old = count - recent

        answerSystemAlerts(["允许访问所有照片", "Allow Full Access", "允许完全访问", "允许", "Allow"], timeout: 8)
        // On a device: local network, and on China-region iPhones the wireless data prompt too.
        for _ in 0..<2 {
            answerSystemAlerts(["无线局域网与蜂窝网络", "允许", "Allow"], timeout: 4)
        }
        let localCells = app.buttons.matching(identifier: "cell-local")
        waitForCount(localCells, count, app: app)

        app.buttons["tab-settings"].tap()
        answerSystemAlerts(["允许", "Allow"], timeout: 3)
        let archiveNow = app.buttons["archive-now"]
        XCTAssertTrue(archiveNow.waitForExistence(timeout: 15))
        waitEnabled(archiveNow)
        archiveNow.tap()
        answerSystemAlerts(["允许", "Allow"], timeout: 3)
        assertArchiveStarted(archiveNow, in: app)

        let free = app.buttons["free-space"]
        scrollTo(free, in: app)
        XCTAssertTrue(
            free.wait(for: \.label, toEqual: "释放手机空间（\(old) 张）", timeout: 120),
            "upload did not finish: \(free.label); \(app.staticTexts["archive-result"].exists ? app.staticTexts["archive-result"].label : "no result")"
        )
        waitEnabled(free)
        free.tap()
        let confirm = app.buttons.matching(identifier: "confirm-free").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        answerSystemAlerts(["删除", "Delete"], timeout: 10)
        XCTAssertTrue(free.wait(for: \.label, toEqual: "释放手机空间（0 张）", timeout: 30))

        app.buttons["tab-library"].tap()
        let nasCells = app.buttons.matching(identifier: "cell-nas")
        waitForCount(nasCells, old, app: app)
        XCTAssertEqual(localCells.count, recent, "photos inside the retention window must stay on the phone")

        // A photo no longer on the phone still opens, with the original from the NAS.
        nasCells.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["viewer-back"].waitForExistence(timeout: 5))
        // This identifier appears only after the NAS's original bytes have decoded; a thumbnail or a local neighbour can't satisfy it.
        XCTAssertTrue(app.descendants(matching: .any)["viewer-image-nas-original"].waitForExistence(timeout: 60), "NAS original did not load")
        XCTAssertFalse(app.descendants(matching: .any)["viewer-error"].exists)

        // Deleting a NAS-only photo warns that it's permanent; backing out keeps it.
        app.buttons["viewer-delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["从 NAS 永久删除"].firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.descendants(matching: .any)["viewer-back"].firstMatch.tap()
        waitForCount(nasCells, old, app: app)
    }

    /// Removes what the test left in the photo library.
    func testZCleanupFixtureAlbum() throws {
        let app = try launch(cleanup: true)
        answerSystemAlerts(["允许访问所有照片", "Allow Full Access"], timeout: 2)
        // iOS's prompts can take a while to appear, and photos and the album may each get one. Leaving before
        // answering would leave photos behind, and the next run would find the album and not reseed it.
        let prompt = springboard.alerts.firstMatch
        var deadline = Date().addingTimeInterval(30)
        var answered = false
        while Date() < deadline {
            if prompt.exists {
                answerSystemAlerts(["删除", "Delete"], timeout: 2)
                answered = true
                deadline = Date().addingTimeInterval(4)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(answered, "iOS never asked to delete the fixtures")
        XCTAssertFalse(prompt.exists, "a delete prompt is still open")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.terminate()
    }

    private func assertArchiveStarted(_ archiveNow: XCUIElement, in app: XCUIApplication) {
        let pause = app.buttons["暂停"]
        let result = app.staticTexts["archive-result"]
        let started = NSPredicate { _, _ in pause.exists || result.exists }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: started, object: nil)], timeout: 15),
            .completed,
            "tapping archive-now started nothing; enabled=\(archiveNow.isEnabled), hittable=\(archiveNow.isHittable)"
        )
    }

    private func waitForCount(_ query: XCUIElementQuery, _ expected: Int, app: XCUIApplication, timeout: TimeInterval = 40) {
        let predicate = NSPredicate { _, _ in query.count == expected }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "found \(query.count), expected \(expected)")
    }

    private func waitEnabled(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 40), .completed, "\(element.identifier) stayed disabled")
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Taps the first matching button on any system alert, then keeps looking until the timeout.
    private func answerSystemAlerts(_ labels: [String], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            if alert.exists {
                for label in labels where alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }
}
