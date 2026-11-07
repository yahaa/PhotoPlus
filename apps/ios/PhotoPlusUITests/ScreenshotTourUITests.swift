import XCTest

/// Saves a screenshot of each screen for visual review, using generated images only.
/// Runs only when TEST_RUNNER_PHOTOPLUS_SCREENSHOT_DIR is set, on a simulator, which can write to the host disk.
/// Never set TEST_RUNNER_PHOTOPLUS_TOUR_UNCONFINED on a device: it would read and upload that device's real photos.
final class ScreenshotTourUITests: XCTestCase {
    func testTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["PHOTOPLUS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_PHOTOPLUS_SCREENSHOT_DIR to run")
        }
        let app = XCUIApplication()
        // A simulator's own sample library exercises the unconfined path, which fixtures bypass.
        let unconfined = env["PHOTOPLUS_TOUR_UNCONFINED"] == "1"
        if !unconfined {
            app.launchEnvironment["PHOTOPLUS_FIXTURE_ALBUM"] = "PhotoPlus Tour Fixture"
            app.launchEnvironment["PHOTOPLUS_FIXTURE_COUNT"] = "40"
        }
        app.launchEnvironment["PHOTOPLUS_SERVER_URL"] = env["PHOTOPLUS_SERVER_URL"]
        app.launchEnvironment["PHOTOPLUS_TOKEN"] = env["PHOTOPLUS_TOKEN"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["允许完全访问"]
        if allow.waitForExistence(timeout: 6) { allow.tap() }

        XCTAssertTrue(app.buttons["cell-local"].firstMatch.waitForExistence(timeout: 30))
        pause(2)
        save(app, "1-all", directory)

        app.segmentedControls["library-mode"].buttons["月"].tap()
        pause(2)
        save(app, "2-months", directory)

        app.segmentedControls["library-mode"].buttons["年"].tap()
        pause(2)
        save(app, "3-years", directory)

        app.segmentedControls["library-mode"].buttons["全部"].tap()
        pause(1)
        app.buttons["cell-local"].firstMatch.tap()
        pause(2)
        save(app, "4-viewer", directory)
        app.descendants(matching: .any)["viewer-back"].tap()
        pause(1)

        app.tabBars.buttons["精选集"].tap()
        pause(2)
        save(app, "5-collections", directory)

        app.tabBars.buttons["设置"].tap()
        pause(2)
        save(app, "6-settings", directory)

        if unconfined {
            let archiveNow = app.buttons["archive-now"]
            XCTAssertTrue(archiveNow.waitForExistence(timeout: 10))
            archiveNow.tap()
            let result = app.staticTexts["archive-result"]
            XCTAssertTrue(result.waitForExistence(timeout: 60))
            save(app, "7-archived", directory)
            print("archive-result: \(result.label)")
        }
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func save(_ app: XCUIApplication, _ name: String, _ directory: String) {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try? app.screenshot().pngRepresentation.write(to: url)
    }
}
