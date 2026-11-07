import XCTest
@testable import PhotoPlus

final class LibraryQueryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private func item(
        _ id: String,
        date: Date = .distantPast,
        kind: MediaKind = .image,
        favorite: Bool = false,
        screenshot: Bool = false,
        local: Bool = true,
        filename: String? = nil
    ) -> PhotoItem {
        let remote = filename.map {
            RemotePhoto(
                id: id, takenAt: date, filename: $0, contentType: "image/jpeg", sizeBytes: 1, tier: .casual,
                width: 1, height: 1, sourceLocalId: "", motionSize: 0, uploadedAt: date
            )
        }
        return PhotoItem(
            id: id, takenAt: date, kind: kind, duration: 0, width: 1, height: 1, isFavorite: favorite, isBurst: false,
            isScreenshot: screenshot, localAssetID: local ? id : nil, remote: remote
        )
    }

    func testFiltersSplitByTypeAndStorage() {
        let photo = item("photo")
        let video = item("video", kind: .video)
        let favorite = item("favorite", favorite: true)
        let screenshot = item("screenshot", screenshot: true)
        let nas = item("nas", local: false, filename: "a.jpg")
        let all = [photo, video, favorite, screenshot, nas]

        XCTAssertEqual(all.filter(LibraryFilter.all.matches), all)
        XCTAssertEqual(all.filter(LibraryFilter.favorites.matches), [favorite])
        XCTAssertEqual(all.filter(LibraryFilter.videos.matches), [video])
        XCTAssertEqual(all.filter(LibraryFilter.screenshots.matches), [screenshot])
        XCTAssertEqual(all.filter(LibraryFilter.nasOnly.matches), [nas])
        XCTAssertEqual(all.filter(LibraryFilter.phoneOnly.matches), [photo, video, favorite, screenshot])
        XCTAssertFalse(all.filter(LibraryFilter.photos.matches).contains(video))
    }

    func testSearchMatchesWholeDateWordsOnly() {
        let january = item("jan", date: date(2024, 1, 5))
        let november = item("nov", date: date(2024, 11, 5))
        let items = [january, november]

        XCTAssertEqual(LibrarySearch.filter(items, query: "1月", calendar: calendar), [january], "1月 must not match 11月")
        XCTAssertEqual(LibrarySearch.filter(items, query: "2024年11月", calendar: calendar), [november])
        XCTAssertEqual(LibrarySearch.filter(items, query: "2024", calendar: calendar), items)
        XCTAssertEqual(LibrarySearch.filter(items, query: "2023", calendar: calendar), [])
    }

    func testSearchCombinesTermsAcrossFields() {
        let target = item("a", date: date(2024, 3, 1), kind: .video)
        let otherYear = item("b", date: date(2023, 3, 1), kind: .video)
        let photo = item("c", date: date(2024, 3, 1))
        XCTAssertEqual(LibrarySearch.filter([target, otherYear, photo], query: "2024 视频", calendar: calendar), [target])
    }

    func testSearchMatchesNASFilenameIgnoringCase() {
        let named = item("a", local: false, filename: "IMG_1234.HEIC")
        XCTAssertEqual(LibrarySearch.filter([named, item("b")], query: "img_12", calendar: calendar), [named])
    }

    func testBlankQueryFindsNothing() {
        XCTAssertEqual(LibrarySearch.filter([item("a")], query: "   ", calendar: calendar), [])
    }

    func testDensityStepsStopAtTheEnds() {
        XCTAssertEqual(GridDensity.three.denser, .five)
        XCTAssertEqual(GridDensity.three.sparser, .single)
        XCTAssertEqual(GridDensity.nine.denser, .nine)
        XCTAssertEqual(GridDensity.single.sparser, .single)
    }

    func testDayGroupsDoNotCollapseIntoMonths() {
        let items = [item("a", date: date(2024, 3, 1)), item("b", date: date(2024, 3, 2))]
        let groups = TimelineGrouper.groups(items, by: [.year, .month, .day], calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
    }
}

final class GridLayoutTableTests: XCTestCase {
    func testMatchesTheMeasuredThreeColumnGrid() {
        // Measured from LazyVGrid at 402 points: row 20, second column.
        let table = GridLayoutTable(aspectRatios: Array(repeating: 1, count: 67), columns: 3, width: 402)
        let frame = table.frame(at: 61)
        XCTAssertEqual(frame.minX, 134.57, accuracy: 0.01)
        XCTAssertEqual(frame.minY, 2691.33, accuracy: 0.01)
        XCTAssertEqual(frame.width, 132.87, accuracy: 0.01)
    }

    func testFindsTheRowAtAHeight() {
        let table = GridLayoutTable(aspectRatios: Array(repeating: 1, count: 10), columns: 3, width: 300)
        XCTAssertEqual(table.index(atY: -50), 0)
        XCTAssertEqual(table.index(atY: 0), 0)
        XCTAssertEqual(table.index(atY: table.frame(at: 3).minY + 1), 3)
        XCTAssertEqual(table.index(atY: 100_000), 9, "past the end it stays on the last row")
    }

    func testSingleColumnUsesEachPhotosOwnHeight() {
        let table = GridLayoutTable(aspectRatios: [2, 0.5, 1], columns: 1, width: 100, spacing: 2)
        XCTAssertEqual(table.frame(at: 0).height, 50)
        XCTAssertEqual(table.frame(at: 1).minY, 52)
        XCTAssertEqual(table.frame(at: 1).height, 200)
        XCTAssertEqual(table.frame(at: 2).minY, 254)
        XCTAssertEqual(table.index(atY: 60), 1)
        XCTAssertEqual(table.index(atY: 300), 2)
    }

    func testEmptyGridHasNoRows() {
        XCTAssertNil(GridLayoutTable(aspectRatios: [], columns: 3, width: 300).index(atY: 0))
        XCTAssertNil(GridLayoutTable(aspectRatios: [], columns: 1, width: 300).index(atY: 0))
    }
}
