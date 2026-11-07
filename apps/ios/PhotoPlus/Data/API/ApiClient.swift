import Foundation

enum ApiError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case unauthorized
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "尚未配置 NAS"
        case .invalidResponse: "NAS 返回了无法识别的响应"
        case .unauthorized: "访问令牌不正确"
        case .status(let code): "NAS 返回错误（\(code)）"
        }
    }
}

struct NASStats: Codable, Equatable {
    let photoCount: Int64
    let totalBytes: Int64
}

/// Metadata sent with an original. The original's PUT commits the photo on the server.
struct OriginalUpload {
    let id: String
    let tier: SafetyTier
    let takenAt: Date
    let filename: String
    let contentType: String
    let width: Int
    let height: Int
    let sourceLocalID: String
    let motionSize: Int64
}

/// HTTP client for the NAS Go API.
struct ApiClient {
    enum Kind: String {
        case original
        case motion
        case thumbnail
    }

    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    func stats() async throws -> NASStats {
        try await decode(NASStats.self, request(path: "stats"))
    }

    /// Every committed photo, following the server's pages.
    func allPhotos() async throws -> [RemotePhoto] {
        struct Page: Decodable {
            let items: [RemotePhoto]
            let nextCursor: String
        }
        var photos: [RemotePhoto] = []
        var cursor = ""
        repeat {
            var query = [URLQueryItem(name: "limit", value: "1000")]
            if !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page = try await decode(Page.self, request(path: "photos", query: query))
            photos += page.items
            cursor = page.nextCursor
        } while !cursor.isEmpty
        return photos
    }

    func download(id: String, kind: Kind) async throws -> Data {
        let (data, response) = try await session.data(for: request(path: "photos/\(id)/\(kind.rawValue)"))
        try check(response)
        return data
    }

    /// Downloads to a temporary file the caller must move.
    func downloadFile(id: String, kind: Kind) async throws -> URL {
        let (url, response) = try await session.download(for: request(path: "photos/\(id)/\(kind.rawValue)"))
        try check(response)
        return url
    }

    func uploadThumbnail(id: String, tier: SafetyTier, data: Data) async throws {
        var req = request(path: "photos/\(id)/thumbnail", query: [URLQueryItem(name: "tier", value: tier.rawValue)], method: "PUT")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: req, from: data)
        try check(response)
    }

    func uploadMotion(id: String, tier: SafetyTier, file: URL, sha256: String) async throws {
        var req = request(path: "photos/\(id)/motion", query: [URLQueryItem(name: "tier", value: tier.rawValue)], method: "PUT")
        req.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        req.setValue(sha256, forHTTPHeaderField: "X-Content-SHA256")
        let (_, response) = try await session.upload(for: req, fromFile: file)
        try check(response)
    }

    func uploadOriginal(_ upload: OriginalUpload, file: URL) async throws {
        let (_, response) = try await session.upload(for: originalRequest(upload), fromFile: file)
        try check(response)
    }

    func originalRequest(_ upload: OriginalUpload) -> URLRequest {
        let query = [
            URLQueryItem(name: "tier", value: upload.tier.rawValue),
            URLQueryItem(name: "takenAt", value: DateCoding.string(from: upload.takenAt)),
            URLQueryItem(name: "filename", value: upload.filename),
            URLQueryItem(name: "width", value: String(upload.width)),
            URLQueryItem(name: "height", value: String(upload.height)),
            URLQueryItem(name: "sourceLocalId", value: upload.sourceLocalID),
            URLQueryItem(name: "motionSize", value: String(upload.motionSize))
        ]
        var req = request(path: "photos/\(upload.id)/original", query: query, method: "PUT")
        req.setValue(upload.contentType, forHTTPHeaderField: "Content-Type")
        return req
    }

    func delete(id: String) async throws {
        let (_, response) = try await session.data(for: request(path: "photos/\(id)", method: "DELETE"))
        try check(response)
    }

    private func request(path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var url = baseURL.appending(path: "api/v1/" + path)
        if !query.isEmpty { url.append(queryItems: query) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func decode<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        try check(response)
        return try DateCoding.decoder.decode(type, from: data)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ApiError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw ApiError.unauthorized
        default: throw ApiError.status(http.statusCode)
        }
    }
}

/// The server writes RFC 3339 with a fractional part only when it is non-zero.
enum DateCoding {
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    static func string(from date: Date) -> String {
        formatter(fractional: true).string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter(fractional: true).date(from: string) ?? formatter(fractional: false).date(from: string)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = DateCoding.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(raw)")
            }
            return date
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCoding.string(from: date))
        }
        return encoder
    }()
}
