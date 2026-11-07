import CryptoKit
import Photos
import UIKit
import UniformTypeIdentifiers

/// A smart album or user album shown in Collections.
struct AlbumSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let count: Int
    let keyAssetID: String?
    let isUserAlbum: Bool
}

/// The resources of one asset, exported to temporary files for upload.
struct ExportedOriginal {
    let file: URL
    let sha256: String
    let filename: String
    let contentType: String
    let motionFile: URL?
    let motionSHA256: String?
    let motionSize: Int64
    let directory: URL
}

enum PhotoKitError: LocalizedError {
    case noPhotoResource
    case edited
    case assetGone
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .noPhotoResource: "找不到这张照片的原始文件"
        case .edited: "已编辑的照片暂不归档"
        case .assetGone: "照片已不在图库中"
        case .thumbnailFailed: "无法生成缩略图"
        }
    }
}

/// PhotoKit access. When a fixture album is set (Debug tests only), every read and
/// mutation is confined to that album, so tests can never touch other photos.
final class PhotoKitStore: @unchecked Sendable {
    static let shared = PhotoKitStore()

    let imageManager = PHCachingImageManager()
    let fixtureAlbumTitle: String?

    init() {
        #if DEBUG
        fixtureAlbumTitle = ProcessInfo.processInfo.environment["PHOTOPLUS_FIXTURE_ALBUM"]
        #else
        fixtureAlbumTitle = nil
        #endif
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Reading

    func fetchLocalAssets() -> [LocalAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeAssetSourceTypes = .typeUserLibrary
        let result: PHFetchResult<PHAsset>
        if let fixtureAlbumTitle {
            guard let album = fixtureAlbum(titled: fixtureAlbumTitle) else { return [] }
            result = PHAsset.fetchAssets(in: album, options: nil)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }
        var assets: [LocalAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(Self.localAsset(asset))
        }
        return assets
    }

    func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func albums() -> [AlbumSummary] {
        if let fixtureAlbumTitle {
            guard let album = fixtureAlbum(titled: fixtureAlbumTitle) else { return [] }
            return [summary(album, title: album.localizedTitle ?? "相簿", symbol: "rectangle.stack", isUserAlbum: true)]
        }
        // Titles are ours: localizedTitle followed the app's bundle language and came back in English.
        struct SmartAlbum {
            let subtype: PHAssetCollectionSubtype
            let symbol: String
            let title: String
        }
        let smart = [
            SmartAlbum(subtype: .smartAlbumUserLibrary, symbol: "photo.on.rectangle", title: "最近项目"),
            SmartAlbum(subtype: .smartAlbumFavorites, symbol: "heart", title: "个人收藏"),
            SmartAlbum(subtype: .smartAlbumVideos, symbol: "video", title: "视频"),
            SmartAlbum(subtype: .smartAlbumSelfPortraits, symbol: "person.crop.square", title: "自拍"),
            SmartAlbum(subtype: .smartAlbumLivePhotos, symbol: "livephoto", title: "实况照片"),
            SmartAlbum(subtype: .smartAlbumPanoramas, symbol: "pano", title: "全景照片"),
            SmartAlbum(subtype: .smartAlbumScreenshots, symbol: "camera.viewfinder", title: "屏幕快照"),
            SmartAlbum(subtype: .smartAlbumBursts, symbol: "square.stack.3d.down.right", title: "连拍快照")
        ]
        var summaries: [AlbumSummary] = []
        for entry in smart {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: entry.subtype, options: nil)
            if let album = result.firstObject {
                summaries.append(summary(album, title: entry.title, symbol: entry.symbol, isUserAlbum: false))
            }
        }
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        user.enumerateObjects { album, _, _ in
            summaries.append(self.summary(album, title: album.localizedTitle ?? "相簿", symbol: "rectangle.stack", isUserAlbum: true))
        }
        return summaries
    }

    func assetIDs(inAlbum albumID: String) -> Set<String> {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else {
            return []
        }
        var ids = Set<String>()
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
            ids.insert(asset.localIdentifier)
        }
        return ids
    }

    private func summary(_ album: PHAssetCollection, title: String, symbol: String, isUserAlbum: Bool) -> AlbumSummary {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: album, options: options)
        return AlbumSummary(
            id: album.localIdentifier,
            title: title,
            symbol: symbol,
            count: assets.count,
            keyAssetID: assets.firstObject?.localIdentifier,
            isUserAlbum: isUserAlbum
        )
    }

    func fixtureAlbum(titled title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }

    private static func localAsset(_ asset: PHAsset) -> LocalAsset {
        let kind: MediaKind
        if asset.mediaType == .video {
            kind = .video
        } else if asset.mediaSubtypes.contains(.photoLive) {
            kind = .livePhoto
        } else {
            kind = .image
        }
        return LocalAsset(
            id: asset.localIdentifier,
            creationDate: asset.creationDate ?? .distantPast,
            kind: kind,
            duration: asset.duration,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            isFavorite: asset.isFavorite,
            isBurst: asset.representsBurst
        )
    }

    // MARK: Changing

    /// Shows iOS's own confirmation. Throws if the user declines.
    func delete(assetIDs: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard assets.count > 0 else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    func setFavorite(_ isFavorite: Bool, assetID: String) async throws {
        guard let asset = asset(id: assetID) else { throw PhotoKitError.assetGone }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = isFavorite
        }
    }

    // MARK: Export

    /// Copies the untouched original (EXIF intact), plus a Live Photo's paired video, to a temp directory.
    func exportOriginal(assetID: String) async throws -> ExportedOriginal {
        guard let asset = asset(id: assetID) else { throw PhotoKitError.assetGone }
        let resources = PHAssetResource.assetResources(for: asset)
        // Edits only exist on the phone; uploading the base photo and removing the local copy would lose them.
        guard !resources.contains(where: { $0.type == .fullSizePhoto || $0.type == .adjustmentData }) else {
            throw PhotoKitError.edited
        }
        guard let photo = resources.first(where: { $0.type == .photo }) else { throw PhotoKitError.noPhotoResource }

        let directory = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let file = directory.appending(path: "original")
            try await write(photo, to: file)
            var motionFile: URL?
            var motionSHA: String?
            var motionSize: Int64 = 0
            if let paired = resources.first(where: { $0.type == .pairedVideo }) {
                let target = directory.appending(path: "motion")
                try await write(paired, to: target)
                motionFile = target
                motionSHA = try Self.sha256(of: target)
                motionSize = try Self.size(of: target)
            }
            return ExportedOriginal(
                file: file,
                sha256: try Self.sha256(of: file),
                filename: photo.originalFilename,
                contentType: UTType(photo.uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream",
                motionFile: motionFile,
                motionSHA256: motionSHA,
                motionSize: motionSize,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// JPEG thumbnail stored on the NAS, so the timeline survives the asset leaving the phone.
    func makeThumbnailJPEG(assetID: String) async throws -> Data {
        guard let asset = asset(id: assetID) else { throw PhotoKitError.assetGone }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let data = image?.jpegData(compressionQuality: 0.75) else { throw PhotoKitError.thumbnailFailed }
        return data
    }

    private func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func size(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
