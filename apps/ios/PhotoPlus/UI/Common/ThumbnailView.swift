import Photos
import SwiftUI

/// Loads one image for the grid and cards: PhotoKit for local items, the NAS cache otherwise.
struct ThumbnailView: View {
    @EnvironmentObject private var settings: AppSettings
    let item: PhotoItem
    var pixelSize: CGFloat = 400
    /// Letterboxes instead of cropping, for the original-aspect grid.
    var fits = false

    @State private var image: UIImage?

    init(item: PhotoItem, pixelSize: CGFloat = 400, fits: Bool = false) {
        self.item = item
        self.pixelSize = pixelSize
        self.fits = fits
        // From memory, so a screen that crossfades in never shows an empty placeholder.
        _image = State(initialValue: ThumbnailMemory.image(for: item, pixels: pixelSize))
    }

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fits ? .fit : .fill)
                }
            }
            .clipped()
            .task(id: item.id) { await load() }
    }

    private func load() async {
        if let assetID = item.localAssetID {
            if let cached = ThumbnailMemory.image(for: item, pixels: pixelSize) {
                image = cached
                return
            }
            for await next in ImageLoader.localImages(assetID: assetID, pixels: pixelSize, mode: .aspectFill, allowNetwork: false) {
                image = next
                ThumbnailMemory.store(next, for: item, pixels: pixelSize)
            }
        } else if let id = item.remote?.id {
            image = try? await ImageCache.shared.thumbnail(id: id, api: settings.apiClient)
        }
    }
}

/// Recently shown thumbnails, by photo and size. NSCache lets iOS reclaim them under memory pressure.
enum ThumbnailMemory {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        return cache
    }()

    private static func key(_ item: PhotoItem, _ pixels: CGFloat) -> NSString {
        "\(item.id)-\(Int(pixels))" as NSString
    }

    static func image(for item: PhotoItem, pixels: CGFloat) -> UIImage? {
        cache.object(forKey: key(item, pixels))
    }

    static func store(_ image: UIImage, for item: PhotoItem, pixels: CGFloat) {
        cache.setObject(image, forKey: key(item, pixels))
    }

    /// Loads ahead of a screen that's about to appear.
    static func preload(_ items: [PhotoItem], pixels: CGFloat) async {
        for item in items where image(for: item, pixels: pixels) == nil {
            guard !Task.isCancelled, let assetID = item.localAssetID else { continue }
            for await next in ImageLoader.localImages(assetID: assetID, pixels: pixels, mode: .aspectFill, allowNetwork: false) {
                store(next, for: item, pixels: pixels)
            }
        }
    }
}

enum ImageLoader {
    /// Yields a fast degraded image first when PhotoKit has one, then the final image.
    static func localImages(assetID: String, pixels: CGFloat, mode: PHImageContentMode, allowNetwork: Bool) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = PhotoKitStore.shared.asset(id: assetID) else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = allowNetwork
            options.resizeMode = .fast
            let manager = PhotoKitStore.shared.imageManager
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: pixels, height: pixels),
                contentMode: mode,
                options: options
            ) { image, info in
                if let image { continuation.yield(image) }
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if !isDegraded { continuation.finish() }
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(requestID) }
        }
    }
}
