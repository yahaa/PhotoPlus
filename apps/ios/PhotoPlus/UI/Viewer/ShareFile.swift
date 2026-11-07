import Photos
import SwiftUI

/// Copies a photo to a temporary file for the share sheet, named as the photo was named.
enum ShareFile {
    static func prepare(_ item: PhotoItem, api: ApiClient?) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let remote = item.remote {
            let source = try await ImageCache.shared.originalFile(id: remote.id, api: api)
            let target = directory.appending(path: remote.filename)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        }
        guard let assetID = item.localAssetID, let asset = PhotoKitStore.shared.asset(id: assetID) else {
            throw PhotoKitError.assetGone
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = [.fullSizePhoto, .fullSizeVideo, .photo, .video]
        guard let resource = preferred.lazy.compactMap({ type in resources.first { $0.type == type } }).first else {
            throw PhotoKitError.noPhotoResource
        }
        let target = directory.appending(path: resource.originalFilename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options)
        return target
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
