import Foundation

protocol PhotoRepository {
    func timeline() async throws -> [PhotoItem]
}

struct StubPhotoRepository: PhotoRepository {
    func timeline() async throws -> [PhotoItem] { [] }
}
