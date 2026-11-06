import Foundation

/// Timeline item: local cache and/or NAS object.
struct PhotoItem: Identifiable, Equatable {
    let id: String
    let takenAt: Date
    let isLocalOriginalPresent: Bool
    let nasObjectKey: String?
}
