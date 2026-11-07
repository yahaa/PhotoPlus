import Photos
import SwiftUI

/// Loads one image for the grid and cards: PhotoKit for local items, the NAS cache otherwise.
struct ThumbnailView: View {
    @EnvironmentObject private var settings: AppSettings
    let item: PhotoItem
    var pixelSize: CGFloat = 400

    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: item.id) { await load() }
    }

    private func load() async {
        if let assetID = item.localAssetID {
            for await next in ImageLoader.localImages(assetID: assetID, pixels: pixelSize, mode: .aspectFill, allowNetwork: false) {
                image = next
            }
        } else if let id = item.remote?.id {
            image = try? await ImageCache.shared.thumbnail(id: id, api: settings.apiClient)
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
