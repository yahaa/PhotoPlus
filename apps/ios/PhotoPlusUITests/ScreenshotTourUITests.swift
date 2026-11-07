import XCTest

/// Walks each screen against the behaviour measured in Apple's Photos, saving screenshots for visual review.
/// Uses generated images only and runs only when TEST_RUNNER_PHOTOPLUS_SCREENSHOT_DIR is set. Only a simulator can
/// write screenshots to the host disk, but a device still checks the assertions, and removes the fixture album after.
/// Never set TEST_RUNNER_PHOTOPLUS_TOUR_UNCONFINED on a device: it would read and upload that device's real photos.
final class ScreenshotTourUITests: XCTestCase {
    private var directory = ""
    private lazy var app = XCUIApplication()

    private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    func testTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["PHOTOPLUS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_PHOTOPLUS_SCREENSHOT_DIR to run")
        }
        self.directory = directory
        if env["PHOTOPLUS_TOUR_UNCONFINED"] != "1" {
            app.launchEnvironment["PHOTOPLUS_FIXTURE_ALBUM"] = "PhotoPlus Tour Fixture"
            app.launchEnvironment["PHOTOPLUS_FIXTURE_COUNT"] = env["PHOTOPLUS_FIXTURE_COUNT"] ?? "40"
        }
        app.launchEnvironment["PHOTOPLUS_SERVER_URL"] = env["PHOTOPLUS_SERVER_URL"]
        app.launchEnvironment["PHOTOPLUS_TOKEN"] = env["PHOTOPLUS_TOKEN"]
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["允许完全访问"]
        if allow.waitForExistence(timeout: 6) { allow.tap() }
        XCTAssertTrue(app.buttons["cell-local"].firstMatch.waitForExistence(timeout: 30))

        libraryAndTimeline()
        menusAndSelection()
        viewer()
        collectionsAndSearch()

        app.buttons["tab-settings"].tap()
        pause(1)
        save("70-settings")
        XCTAssertTrue(app.buttons["archive-now"].exists || app.staticTexts["archive-result"].exists || app.buttons["free-space"].exists)

        pinchToOneColumn()
        if env["PHOTOPLUS_TOUR_UNCONFINED"] != "1" { removeFixtures() }
    }

    /// Last because XCUITest can't pinch back: a scale below 1 had no effect here, nor in Apple's Photos.
    private func pinchToOneColumn() {
        app.buttons["tab-library"].tap()
        pause(1)
        let cells = app.buttons.matching(identifier: "cell-local")
        let columnWidth = cells.element(boundBy: cells.count - 1).frame.width
        app.pinch(withScale: 3, velocity: 2)
        pause(1.5)
        save("17-pinch-one-column")
        XCTAssertGreaterThan(cells.element(boundBy: cells.count - 1).frame.width, columnWidth * 2, "pinching out shows one column")
    }

    private func removeFixtures() {
        app.terminate()
        app.launchEnvironment["PHOTOPLUS_FIXTURE_COUNT"] = nil
        app.launchEnvironment["PHOTOPLUS_FIXTURE_CLEANUP"] = "1"
        app.launch()
        let delete = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "the fixture album must really be removed")
        delete.tap()
        // The album can get its own prompt after the photos'.
        if delete.waitForExistence(timeout: 4) { delete.tap() }
        pause(3)
    }

    private func libraryAndTimeline() {
        pause(2)
        save("10-root")
        XCTAssertTrue(app.buttons["tab-library"].exists, "tabs show at the newest photo")
        XCTAssertFalse(app.buttons["mode-all"].exists, "the mode picker is hidden at the newest photo")
        XCTAssertFalse(app.staticTexts["grid-footer"].exists)

        app.swipeDown()
        pause(1.5)
        save("11-away")
        XCTAssertTrue(app.buttons["mode-all"].waitForExistence(timeout: 3), "the bar collapses away from the newest photo")
        XCTAssertFalse(app.buttons["tab-library"].exists)

        app.buttons["mode-months"].tap()
        pause(1.5)
        save("12-months")
        app.buttons["mode-years"].tap()
        pause(1.5)
        save("13-years")
        XCTAssertTrue(app.buttons["mode-years"].isSelected)

        app.buttons["year-card"].firstMatch.tap()
        pause(1.5)
        save("14-year-tap")
        XCTAssertTrue(app.buttons["mode-months"].isSelected, "a year opens Months")
        app.buttons["month-card"].firstMatch.tap()
        pause(1.5)
        save("15-month-tap")
        XCTAssertTrue(app.buttons["mode-all"].isSelected, "a month opens All")

        app.buttons["tab-expand"].tap()
        pause(0.5)
        app.buttons["tab-library"].tap()
        pause(1.5)
        save("16-back-to-newest")
        XCTAssertFalse(app.buttons["mode-all"].exists, "reselecting the tab returns to the newest photo")
    }

    private func menusAndSelection() {
        app.buttons["filter-menu"].firstMatch.tap()
        pause(1)
        save("20-filter-menu")
        app.buttons["筛选"].firstMatch.tap()
        pause(1)
        save("21-filter-sub")
        app.buttons["个人收藏"].firstMatch.tap()
        pause(1.5)
        save("21b-filtered")
        app.buttons["filter-menu"].firstMatch.tap()
        pause(1)
        any("filter-remove").firstMatch.tap()
        pause(1.5)
        XCTAssertTrue(app.buttons["cell-local"].firstMatch.waitForExistence(timeout: 3), "removing the filter brings the photos back")

        let cell = app.buttons["cell-local"].firstMatch
        let last = app.buttons.matching(identifier: "cell-local").element(boundBy: app.buttons.matching(identifier: "cell-local").count - 1)
        last.press(forDuration: 1.2)
        pause(1)
        save("22-longpress")
        app.buttons["拷贝"].firstMatch.tap()
        pause(1)

        app.buttons["select-button"].firstMatch.tap()
        pause(1)
        save("23-select-empty")
        XCTAssertFalse(app.buttons["tab-library"].exists, "the selection bar replaces the tabs")
        XCTAssertFalse(app.buttons["selection-delete"].isEnabled)
        last.tap()
        pause(1)
        save("24-select-one")
        XCTAssertTrue(app.buttons["selection-delete"].isEnabled)
        XCTAssertEqual(any("selection-title").label, "已选择 1 张照片")
        app.buttons["selection-more"].firstMatch.tap()
        pause(1)
        save("25-select-more")
        closeMenu()
        app.buttons["selection-close"].firstMatch.tap()
        pause(1)
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 3))
        XCTAssertTrue(cell.exists)
    }

    private func viewer() {
        let cells = app.buttons.matching(identifier: "cell-local")
        cells.element(boundBy: cells.count - 2).tap()
        XCTAssertTrue(any("viewer-back").waitForExistence(timeout: 5))
        pause(2)
        save("30-viewer")
        XCTAssertTrue(any("viewer-strip").exists)
        let startDate = any("viewer-date").label

        app.swipeLeft()
        pause(1.5)
        save("31-swipe-left")
        XCTAssertNotEqual(any("viewer-date").label, startDate, "the date follows the page")

        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        center.tap()
        pause(1)
        save("32-tap-hidden")
        XCTAssertFalse(any("viewer-back").exists, "a tap hides the bars")
        center.tap()
        pause(1)
        XCTAssertTrue(any("viewer-back").exists)

        center.doubleTap()
        pause(1)
        save("33-double-tap")
        XCTAssertFalse(any("viewer-back").exists, "double-tap fills and hides the bars")
        center.doubleTap()
        pause(1)
        save("34-double-tap-back")
        XCTAssertTrue(any("viewer-back").exists)

        viewerMenuAndInfo()
    }

    private func viewerMenuAndInfo() {
        any("viewer-more").firstMatch.tap()
        pause(1)
        save("35-viewer-more")
        closeMenu()

        any("viewer-info").firstMatch.tap()
        pause(1.5)
        save("36-info")
        XCTAssertTrue(any("info-panel").exists)
        XCTAssertFalse(any("viewer-back").exists, "the panel takes over from the top bar")
        any("viewer-info").firstMatch.tap()
        pause(1)
        XCTAssertFalse(any("info-panel").exists)

        drag(from: 0.55, to: 0.2)
        pause(1.5)
        save("37-swipe-up-info")
        XCTAssertTrue(any("info-panel").exists, "swiping up opens the panel")
        drag(from: 0.25, to: 0.7)
        pause(1.5)
        save("38-swipe-down-info")
        XCTAssertFalse(any("info-panel").exists, "swiping down closes the panel without leaving")
        XCTAssertTrue(any("viewer-back").exists)

        drag(from: 0.3, to: 0.85)
        pause(1.5)
        save("39-swipe-down-exit")
        XCTAssertFalse(any("viewer-back").exists, "swiping down leaves the viewer")
        XCTAssertTrue(app.buttons["select-button"].firstMatch.exists)
    }

    private func collectionsAndSearch() {
        app.buttons["tab-collections"].tap()
        pause(2)
        save("50-collections")
        any("pinned-favorites").firstMatch.tap()
        pause(1.5)
        save("51-empty-album")
        XCTAssertTrue(any("empty-album").firstMatch.exists)
        XCTAssertFalse(app.buttons["tab-collections"].exists, "albums hide the tabs")
        app.navigationBars.buttons.firstMatch.tap()
        pause(1)
        XCTAssertTrue(app.buttons["tab-collections"].waitForExistence(timeout: 3))

        app.buttons["tab-search"].tap()
        pause(1.5)
        save("60-search")
        let field = any("search-field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("2024")
        pause(1.5)
        save("61-search-results")
        field.typeText("zzz")
        pause(1)
        save("62-search-empty")
        XCTAssertTrue(any("search-empty").firstMatch.exists)
        any("search-close").firstMatch.tap()
        pause(1)
        XCTAssertTrue(app.buttons["tab-collections"].isSelected, "closing search returns to the previous tab")
    }

    /// Taps away from a menu, which sit at the trailing edge.
    private func closeMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.7)).tap()
        pause(1)
    }

    private func drag(from start: CGFloat, to end: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)))
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func save(_ name: String) {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try? app.screenshot().pngRepresentation.write(to: url)
    }
}
