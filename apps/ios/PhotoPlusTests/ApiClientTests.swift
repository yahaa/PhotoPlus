import XCTest
@testable import PhotoPlus

final class ApiClientTests: XCTestCase {
    func testDecodesServerPhotoWithAndWithoutFractionalSeconds() throws {
        let json = """
        {"id":"abc","takenAt":"2024-03-01T08:00:00Z","filename":"照片.HEIC","contentType":"image/heic","sizeBytes":12,
         "tier":"important","width":10,"height":20,"sourceLocalId":"X/L0/001","motionSize":0,"uploadedAt":"2026-11-06T17:38:11.778Z"}
        """
        let photo = try DateCoding.decoder.decode(RemotePhoto.self, from: Data(json.utf8))
        XCTAssertEqual(photo.tier, .important)
        XCTAssertEqual(photo.takenAt.timeIntervalSince1970, 1_709_280_000, accuracy: 0.001)
        XCTAssertEqual(photo.uploadedAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.778, accuracy: 0.001)
    }

    func testCachedIndexRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        let photo = RemotePhoto(id: "a", takenAt: date, filename: "a", contentType: "image/jpeg", sizeBytes: 1, tier: .casual,
                                width: 1, height: 1, sourceLocalId: "", motionSize: 0, uploadedAt: date)
        let data = try DateCoding.encoder.encode([photo])
        XCTAssertEqual(try DateCoding.decoder.decode([RemotePhoto].self, from: data), [photo])
    }

    func testOriginalRequestEncodesMetadataAndAuth() throws {
        let client = ApiClient(baseURL: try XCTUnwrap(URL(string: "http://nas.local:8080")), token: "tok")
        let upload = OriginalUpload(id: "abc", tier: .important, takenAt: Date(timeIntervalSince1970: 0), filename: "照片 1.HEIC",
                                    contentType: "image/heic", width: 4, height: 3, sourceLocalID: "A/L0/001", motionSize: 7)
        let request = client.originalRequest(upload)
        let url = try XCTUnwrap(request.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path(), "/api/v1/photos/abc/original")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(values["filename"], "照片 1.HEIC")
        XCTAssertEqual(values["sourceLocalId"], "A/L0/001")
        XCTAssertEqual(values["motionSize"], "7")
        XCTAssertEqual(values["takenAt"], "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/heic")
    }

    @MainActor
    func testSettingsRejectUnusableServerAddresses() throws {
        let suite = "ApiClientTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let savedToken = settings.token
        defer { settings.token = savedToken }
        settings.token = "tok"
        for bad in ["", "nas.local", "ftp://nas.local", "http://"] {
            settings.serverURLString = bad
            XCTAssertNil(settings.apiClient, bad)
        }
        settings.serverURLString = " http://192.168.1.10:8080 "
        XCTAssertNotNil(settings.apiClient)
        settings.token = ""
        XCTAssertNil(settings.apiClient)
    }
}
