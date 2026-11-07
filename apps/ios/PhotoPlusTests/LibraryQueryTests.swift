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
