import Photos
import UIKit

/// The merged timeline. Phone and NAS are the only sources of truth; the index file
/// below only keeps NAS photos visible while the NAS is unreachable.
@MainActor
final class LibraryStore: NSObject, ObservableObject {
    enum NASState: Equatable {
        case notConfigured
        case connected
        case unreachable(String)
    }

    @Published private(set) var items: [PhotoItem] = []
    @Published private(set) var authorization: PHAuthorizationStatus = .notDetermined
    @Published private(set) var nasState: NASState = .notConfigured
    @Published private(set) var nasStats: NASStats?
    @Published private(set) var hasLoaded = false

    let settings: AppSettings
    let photoKit: PhotoKitStore

    private var local: [LocalAsset] = []
    private var remote: [RemotePhoto] = []
    private let indexFile: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "remote-index.json")
    private var reloadTask: Task<Void, Never>?

    init(settings: AppSettings, photoKit: PhotoKitStore = .shared) {
        self.settings = settings
        self.photoKit = photoKit
        super.init()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func start() async {
        authorization = await photoKit.requestAuthorization()
        #if DEBUG
        await FixtureSeeder.seedIfRequested(photoKit: photoKit)
        #endif
        if authorization == .authorized || authorization == .limited {
            PHPhotoLibrary.shared().register(self)
        }
        if let data = try? Data(contentsOf: indexFile),
           let cached = try? DateCoding.decoder.decode([RemotePhoto].self, from: data) {
            remote = cached
        }
        await reload()
    }

    func reload() async {
        await reloadLocal()
        await refreshRemote()
    }

    func reloadLocal() async {
        guard authorization == .authorized || authorization == .limited else {
            local = []
            publish()
            return
        }
        let photoKit = photoKit
        local = await Task.detached(priority: .userInitiated) { photoKit.fetchLocalAssets() }.value
        publish()
    }

    /// Best effort: on failure the timeline keeps the last known NAS photos.
    func refreshRemote() async {
        do {
            try await fetchRemoteStrict()
        } catch {
            nasState = settings.apiClient == nil ? .notConfigured : .unreachable(error.localizedDescription)
            publish()
        }
    }

    /// Fails instead of falling back to the cached index. Anything about to delete
    /// local data must go through this, so it never trusts a stale view of the NAS.
    func fetchRemoteStrict() async throws {
        guard let api = settings.apiClient else { throw ApiError.notConfigured }
        async let photos = api.allPhotos()
        async let stats = api.stats()
        let (fetchedPhotos, fetchedStats) = try await (photos, stats)
        remote = fetchedPhotos
        nasStats = fetchedStats
        nasState = .connected
        if let data = try? DateCoding.encoder.encode(fetchedPhotos) {
            try? data.write(to: indexFile, options: .atomic)
        }
        publish()
    }

    // MARK: Changes

    /// Removes phone copies, and NAS copies too when `includingNAS`. The phone goes first
    /// because iOS asks for confirmation there; declining stops everything.
    func delete(_ targets: [PhotoItem], includingNAS: Bool) async throws {
        let localIDs = targets.compactMap(\.localAssetID)
        if !localIDs.isEmpty {
            try await photoKit.delete(assetIDs: localIDs)
        }
        let remoteIDs = targets.filter { includingNAS || $0.storage == .nasOnly }.compactMap(\.remote?.id)
        if !remoteIDs.isEmpty {
            guard let api = settings.apiClient else { throw ApiError.notConfigured }
            for id in remoteIDs {
                try await api.delete(id: id)
                ImageCache.shared.forget(id: id)
            }
        }
        await reload()
    }

    func setFavorite(_ isFavorite: Bool, item: PhotoItem) async {
        guard let id = item.localAssetID else { return }
        try? await photoKit.setFavorite(isFavorite, assetID: id)
        await reloadLocal()
    }

    private func publish() {
        items = TimelineMerger.merge(local: local, remote: remote)
        hasLoaded = true
    }
}

extension LibraryStore: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            // A batch of changes arrives as many callbacks; refetch once they settle.
            self.reloadTask?.cancel()
            self.reloadTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await self.reloadLocal()
            }
        }
    }
}
