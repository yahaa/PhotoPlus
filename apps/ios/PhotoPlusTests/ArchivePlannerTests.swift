import XCTest
@testable import PhotoPlus

final class ArchivePlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var cutoff: Date { ArchivePlanner.cutoff(now: now, retentionMonths: 6) }
    private var old: Date { now.addingTimeInterval(-86_400 * 365) }
    private var recent: Date { now.addingTimeInterval(-86_400 * 10) }

    func testUploadsOnlyOldPhotosWithoutNASCopy() {
        let items = [
            item("old", at: old),
            item("recent", at: recent),
            item("alreadyOnNAS", at: old, remote: remote()),
            nasOnly(at: old)
        ]
        XCTAssertEqual(ArchivePlanner.uploadCandidates(in: items, cutoff: cutoff).map(\.id), ["old"])
    }

    func testVideosAndBurstsStayOnThePhone() {
        let items = [item("video", at: old, kind: .video), item("burst", at: old, isBurst: true)]
        XCTAssertTrue(ArchivePlanner.uploadCandidates(in: items, cutoff: cutoff).isEmpty)
        XCTAssertEqual(ArchivePlanner.skippedCount(in: items, cutoff: cutoff), 2)
    }

    func testNeverFreesWithoutNASCopy() {
        XCTAssertTrue(ArchivePlanner.freeableItems(in: [item("old", at: old)], cutoff: cutoff).isEmpty)
    }

    func testNeverFreesInsideRetentionWindow() {
        let items = [item("recent", at: recent, remote: remote())]
        XCTAssertTrue(ArchivePlanner.freeableItems(in: items, cutoff: cutoff).isEmpty)
    }

    func testFreesOldPhotoWithNASCopy() {
        let items = [item("old", at: old, remote: remote())]
        XCTAssertEqual(ArchivePlanner.freeableItems(in: items, cutoff: cutoff).map(\.id), ["old"])
    }

    func testLivePhotoNeedsMotionOnNASBeforeFreeing() {
        let stillOnly = item("a", at: old, kind: .livePhoto, remote: remote(motionSize: 0))
        let complete = item("b", at: old, kind: .livePhoto, remote: remote(motionSize: 42))
        XCTAssertEqual(ArchivePlanner.freeableItems(in: [stillOnly, complete], cutoff: cutoff).map(\.id), ["b"])
    }

    func testCutoffUsesCalendarMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let august31 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)) ?? now
        let result = ArchivePlanner.cutoff(now: august31, retentionMonths: 6, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: result), DateComponents(month: 2, day: 28))
    }

    private func item(_ id: String, at date: Date, kind: MediaKind = .image, isBurst: Bool = false, remote: RemotePhoto? = nil) -> PhotoItem {
        PhotoItem(id: id, takenAt: date, kind: kind, duration: 0, width: 1, height: 1, isFavorite: false, isBurst: isBurst, localAssetID: id, remote: remote)
    }

    private func nasOnly(at date: Date) -> PhotoItem {
        PhotoItem(id: "nas", takenAt: date, kind: .image, duration: 0, width: 1, height: 1, isFavorite: false, isBurst: false,
                  localAssetID: nil, remote: remote())
    }

    private func remote(motionSize: Int64 = 0) -> RemotePhoto {
        RemotePhoto(id: "hash", takenAt: old, filename: "a.jpg", contentType: "image/jpeg", sizeBytes: 1, tier: .casual,
                    width: 1, height: 1, sourceLocalId: "", motionSize: motionSize, uploadedAt: now)
    }
}
