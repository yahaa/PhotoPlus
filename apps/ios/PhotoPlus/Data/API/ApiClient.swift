import Foundation

/// HTTP client for the NAS Go API.
/// TODO: auth headers, timeline fetch, original download, multipart upload (EXIF preserved).
struct ApiClient {
    var baseURL: URL?

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }
}
