import ImageIO
import UIKit

/// On-disk caches for NAS images. They live in Caches, so iOS may purge them; everything is re-fetchable.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let thumbnails: URL
    private let originals: URL
    /// Originals kept for quick re-opening. The app must not quietly grow back what archiving freed.
    static let originalsLimitBytes: Int64 = 1 << 30

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        thumbnails = base.appending(path: "thumbnails", directoryHint: .isDirectory)
        originals = base.appending(path: "originals", directoryHint: .isDirectory)
        for directory in [thumbnails, originals] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        memory.countLimit = 600
    }

    func thumbnail(id: String, api: ApiClient?) async throws -> UIImage {
        if let cached = memory.object(forKey: id as NSString) { return cached }
        let file = thumbnails.appending(path: id)
        if let image = UIImage(contentsOfFile: file.path) {
            memory.setObject(image, forKey: id as NSString)
            return image
        }
        guard let api else { throw ApiError.notConfigured }
        let data = try await api.download(id: id, kind: .thumbnail)
        try data.write(to: file, options: .atomic)
        guard let image = UIImage(data: data) else { throw ApiError.invalidResponse }
        memory.setObject(image, forKey: id as NSString)
        return image
    }

    /// Stores a thumbnail at upload time, so it is there the moment the local copy goes away.
    func storeThumbnail(_ data: Data, id: String) {
        try? data.write(to: thumbnails.appending(path: id), options: .atomic)
    }

    func originalFile(id: String, api: ApiClient?) async throws -> URL {
        let target = originals.appending(path: id)
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            return target
        }
        guard let api else { throw ApiError.notConfigured }
        let temporary = try await api.downloadFile(id: id, kind: .original)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        trimOriginals(limit: Self.originalsLimitBytes)
        return target
    }

    /// Removes the least recently opened originals until the cache fits in `limit`.
    func trimOriginals(limit: Int64) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: originals, includingPropertiesForKeys: keys)) ?? []
        struct Entry {
            let url: URL
            let date: Date
            let size: Int64
        }
        let entries: [Entry] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(url: url, date: values.contentModificationDate ?? .distantPast, size: Int64(values.fileSize ?? 0))
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > limit {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    func forget(id: String) {
        memory.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: thumbnails.appending(path: id))
        try? FileManager.default.removeItem(at: originals.appending(path: id))
    }

    /// Decodes at display size, because a 12 MP photo decoded in full costs about 48 MB.
    static func downsampled(file: URL, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
