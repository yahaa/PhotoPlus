import CryptoKit
import Photos
import UIKit
import UniformTypeIdentifiers

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

extension PhotoKitStore {
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
