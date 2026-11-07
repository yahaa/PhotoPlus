import Photos
import UIKit

/// A smart album or user album shown in Collections.
struct AlbumSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let count: Int
    let keyAssetID: String?
    let isUserAlbum: Bool
}

enum PhotoKitError: LocalizedError {
    case noPhotoResource
    case edited
    case assetGone
    case thumbnailFailed
    case confinedToFixture

    var errorDescription: String? {
        switch self {
        case .noPhotoResource: "找不到这张照片的原始文件"
        case .edited: "已编辑的照片暂不归档"
        case .assetGone: "照片已不在图库中"
        case .thumbnailFailed: "无法生成缩略图"
        case .confinedToFixture: "测试模式下不可用"
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
            isBurst: asset.representsBurst,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot)
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

    func setFavorite(_ isFavorite: Bool, assetIDs: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            assets.enumerateObjects { asset, _, _ in
                PHAssetChangeRequest(for: asset).isFavorite = isFavorite
            }
        }
    }

    func hide(assetIDs: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            assets.enumerateObjects { asset, _, _ in
                PHAssetChangeRequest(for: asset).isHidden = true
            }
        }
    }

    /// Adds a second copy of a photo, keeping its bytes and capture date.
    func duplicate(assetID: String) async throws {
        guard fixtureAlbumTitle == nil else { throw PhotoKitError.confinedToFixture }
        guard let asset = asset(id: assetID) else { throw PhotoKitError.assetGone }
        let data = try await imageData(assetID: assetID)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            request.creationDate = asset.creationDate
            request.location = asset.location
        }
    }

    func addAssets(_ assetIDs: [String], toAlbum albumID: String) async throws {
        guard fixtureAlbumTitle == nil else { throw PhotoKitError.confinedToFixture }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else {
            throw PhotoKitError.assetGone
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets)
        }
    }

    func createAlbum(title: String) async throws {
        guard fixtureAlbumTitle == nil else { throw PhotoKitError.confinedToFixture }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
        }
    }

    /// The current rendition's bytes, for copying and for reading EXIF.
    func imageData(assetID: String) async throws -> Data {
        guard let asset = asset(id: assetID) else { throw PhotoKitError.assetGone }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: info?[PHImageErrorKey] as? Error ?? PhotoKitError.noPhotoResource)
                }
            }
        }
    }

    func originalFilename(assetID: String) -> String? {
        guard let asset = asset(id: assetID) else { return nil }
        return PHAssetResource.assetResources(for: asset).first?.originalFilename
    }
}
