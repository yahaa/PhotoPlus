import XCTest
@testable import PhotoPlus

final class ImageCacheTests: XCTestCase {
    func testTrimRemovesLeastRecentlyUsedOriginalsFirst() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ImageCache(root: root)
        let originals = root.appending(path: "originals")
        let now = Date()
        for (name, age) in [("oldest", 300.0), ("middle", 200.0), ("newest", 100.0)] {
            let file = originals.appending(path: name)
            try Data(count: 100).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        cache.trimOriginals(limit: 150)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: originals.path)
        XCTAssertEqual(remaining, ["newest"])
    }
}
