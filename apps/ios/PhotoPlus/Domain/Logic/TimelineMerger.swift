import Foundation

/// Builds the single timeline from the phone's library and the NAS index.
enum TimelineMerger {
    /// Items sorted oldest first, the order Photos lays out its grid.
    /// A NAS photo pairs with a local asset through `sourceLocalId`, so nothing appears twice.
    static func merge(local: [LocalAsset], remote: [RemotePhoto]) -> [PhotoItem] {
        var remoteBySource: [String: RemotePhoto] = [:]
        for photo in remote where !photo.sourceLocalId.isEmpty {
            remoteBySource[photo.sourceLocalId] = photo
        }
        var pairedRemoteIDs = Set<String>()
        var items: [PhotoItem] = local.map { asset in
            let paired = remoteBySource[asset.id]
            if let paired { pairedRemoteIDs.insert(paired.id) }
            return PhotoItem(
                id: asset.id,
                takenAt: asset.creationDate,
                kind: asset.kind,
                duration: asset.duration,
                width: asset.width,
                height: asset.height,
                isFavorite: asset.isFavorite,
                isBurst: asset.isBurst,
                localAssetID: asset.id,
                remote: paired
            )
        }
        for photo in remote where !pairedRemoteIDs.contains(photo.id) {
            items.append(PhotoItem(
                id: photo.id,
                takenAt: photo.takenAt,
                kind: photo.motionSize > 0 ? .livePhoto : .image,
                duration: 0,
                width: photo.width,
                height: photo.height,
                isFavorite: false,
                isBurst: false,
                localAssetID: nil,
                remote: photo
            ))
        }
        return items.sorted { lhs, rhs in
            lhs.takenAt == rhs.takenAt ? lhs.id < rhs.id : lhs.takenAt < rhs.takenAt
        }
    }
}
