import XCTest
@testable import PhotoPlus

final class TimelineMergerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testPairsThroughSourceLocalIDSoNothingAppearsTwice() {
        let items = TimelineMerger.merge(local: [local("A", 0)], remote: [remote("hash", source: "A", 0)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].storage, .both)
        XCTAssertEqual(items[0].remote?.id, "hash")
    }

    func testPhotoGoneFromPhoneStaysOnTimelineAsNASOnly() {
        let items = TimelineMerger.merge(local: [], remote: [remote("hash", source: "A", 0)])
        XCTAssertEqual(items.map(\.storage), [.nasOnly])
        XCTAssertEqual(items[0].id, "hash")
    }

    func testSortsOldestFirstAcrossSources() {
        let items = TimelineMerger.merge(
            local: [local("newest", 200), local("oldest", 0)],
            remote: [remote("middle", source: "elsewhere", 100)]
        )
        XCTAssertEqual(items.map(\.id), ["oldest", "middle", "newest"])
    }

    func testRemoteWithMotionIsLivePhoto() {
        let items = TimelineMerger.merge(local: [], remote: [remote("hash", source: "", 0, motionSize: 9)])
        XCTAssertEqual(items[0].kind, .livePhoto)
    }

    func testGroupsByMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let dates = [(2024, 1, 5), (2024, 1, 20), (2024, 3, 1)].compactMap {
            calendar.date(from: DateComponents(year: $0.0, month: $0.1, day: $0.2))
        }
        let items = dates.enumerated().map { index, date in
            let asset = LocalAsset(id: "\(index)", creationDate: date, kind: .image, duration: 0, width: 1, height: 1, isFavorite: false, isBurst: false)
            return TimelineMerger.merge(local: [asset], remote: [])[0]
        }
        let groups = TimelineGrouper.groups(items, by: [.year, .month], calendar: calendar)
        XCTAssertEqual(groups.map(\.items.count), [2, 1])
    }

    private func local(_ id: String, _ offset: TimeInterval) -> LocalAsset {
        LocalAsset(id: id, creationDate: base.addingTimeInterval(offset), kind: .image, duration: 0, width: 1, height: 1, isFavorite: false, isBurst: false)
    }

    private func remote(_ id: String, source: String, _ offset: TimeInterval, motionSize: Int64 = 0) -> RemotePhoto {
        RemotePhoto(id: id, takenAt: base.addingTimeInterval(offset), filename: "a.jpg", contentType: "image/jpeg", sizeBytes: 1, tier: .casual,
                    width: 1, height: 1, sourceLocalId: source, motionSize: motionSize, uploadedAt: base)
    }
}
