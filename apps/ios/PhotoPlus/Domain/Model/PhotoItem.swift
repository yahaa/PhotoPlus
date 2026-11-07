import Foundation

enum MediaKind: Hashable {
    case image
    case livePhoto
    case video
}

/// Metadata of an asset in the phone's photo library.
struct LocalAsset: Hashable {
    let id: String
    let creationDate: Date
    let kind: MediaKind
    let duration: TimeInterval
    let width: Int
    let height: Int
    let isFavorite: Bool
    let isBurst: Bool
}

/// A photo committed on the NAS. Mirrors the server's JSON.
struct RemotePhoto: Codable, Hashable, Identifiable {
    let id: String
    let takenAt: Date
    let filename: String
    let contentType: String
    let sizeBytes: Int64
    let tier: SafetyTier
    let width: Int
    let height: Int
    let sourceLocalId: String
    let motionSize: Int64
    let uploadedAt: Date
}

/// One timeline entry: on the phone, on the NAS, or both.
struct PhotoItem: Identifiable, Hashable {
    enum Storage {
        case localOnly
        case both
        case nasOnly
    }

    let id: String
    let takenAt: Date
    let kind: MediaKind
    let duration: TimeInterval
    let width: Int
    let height: Int
    let isFavorite: Bool
    let isBurst: Bool
    let localAssetID: String?
    let remote: RemotePhoto?

    var storage: Storage {
        switch (localAssetID, remote) {
        case (.some, .some): .both
        case (.some, .none): .localOnly
        default: .nasOnly
        }
    }

    var aspectRatio: CGFloat {
        width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 1
    }
}
