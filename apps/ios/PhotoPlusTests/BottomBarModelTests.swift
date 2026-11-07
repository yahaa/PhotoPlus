import XCTest
@testable import PhotoPlus

@MainActor
final class BottomBarModelTests: XCTestCase {
    func testCollapsesOnlyAwayFromNewestOrOutsideAll() {
        let model = BottomBarModel()
        XCTAssertFalse(model.isCollapsed)
        model.setAwayFromNewest(true)
        XCTAssertTrue(model.isCollapsed)
        model.setAwayFromNewest(false)
        XCTAssertFalse(model.isCollapsed)
        model.mode = .months
        XCTAssertTrue(model.isCollapsed, "Years and Months stay collapsed even at the newest photo")
    }

    func testOtherTabsNeverCollapse() {
        let model = BottomBarModel()
        model.setAwayFromNewest(true)
        model.tab = .settings
        XCTAssertFalse(model.isCollapsed)
    }

    func testTappingCollapsedIconExpandsUntilScrollingAgain() {
        let model = BottomBarModel()
        model.setAwayFromNewest(true)
        model.expand()
        XCTAssertFalse(model.isCollapsed)
        model.setAwayFromNewest(false)
        model.setAwayFromNewest(true)
        XCTAssertTrue(model.isCollapsed)
    }

    func testReselectingLibraryReturnsToNewest() {
        let model = BottomBarModel()
        model.mode = .years
        model.select(.library)
        XCTAssertEqual(model.mode, .all)
        XCTAssertEqual(model.scrollToNewestRequests, 1)
    }

    func testSearchRemembersWhereItCameFrom() {
        let model = BottomBarModel()
        model.select(.collections)
        model.select(.search)
        XCTAssertTrue(model.isHidden)
        XCTAssertEqual(model.previousTab, .collections)
    }

    func testHidingNeedsEveryOwnerToRelease() {
        let model = BottomBarModel()
        let first = UUID()
        let second = UUID()
        model.setHidden(true, by: first)
        model.setHidden(true, by: second)
        model.setHidden(false, by: first)
        XCTAssertTrue(model.isHidden)
        model.setHidden(false, by: second)
        XCTAssertFalse(model.isHidden)
    }
}
