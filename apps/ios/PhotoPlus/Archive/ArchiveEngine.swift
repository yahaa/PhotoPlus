import Foundation

/// Runs the rolling archive in the foreground: upload, verify, and on request free the phone.
/// There is no queue to persist: phone and NAS already say what is left, so a rescan resumes.
@MainActor
final class ArchiveEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case uploading(done: Int, total: Int)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var failures: [String] = []
    @Published private(set) var editedSkipped = 0
    @Published private(set) var lastResult: String?

    private let store: LibraryStore
    private var task: Task<Void, Never>?
    private var editedIDs = Set<String>()

    init(store: LibraryStore) {
        self.store = store
    }

    private var cutoff: Date {
        ArchivePlanner.cutoff(now: Date(), retentionMonths: store.settings.retentionMonths)
    }

    var pending: [PhotoItem] {
        ArchivePlanner.uploadCandidates(in: store.items, cutoff: cutoff).filter { !editedIDs.contains($0.id) }
    }

    var freeable: [PhotoItem] {
        ArchivePlanner.freeableItems(in: store.items, cutoff: cutoff)
    }

    var skippedCount: Int {
        ArchivePlanner.skippedCount(in: store.items, cutoff: cutoff) + editedSkipped
    }

    func start() {
        guard phase == .idle, store.settings.apiClient != nil else { return }
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
    }

    private func run() async {
        guard let api = store.settings.apiClient else { return }
        failures = []
        lastResult = nil
        // A NAS photo missing from a stale index would upload again; start from the current state.
        do {
            try await store.fetchRemoteStrict()
        } catch {
            lastResult = "无法连接 NAS：\(error.localizedDescription)"
            return
        }
        let batch = pending
        let tier = store.settings.tier
        var uploaded = 0
        phase = .uploading(done: 0, total: batch.count)
        for (offset, item) in batch.enumerated() {
            if Task.isCancelled { break }
            do {
                try await upload(item, api: api, tier: tier)
                uploaded += 1
            } catch PhotoKitError.edited {
                editedIDs.insert(item.id)
                editedSkipped = editedIDs.count
            } catch is CancellationError {
                break
            } catch let error as URLError where error.code == .cancelled {
                break
            } catch {
                failures.append(error.localizedDescription)
            }
            phase = .uploading(done: offset + 1, total: batch.count)
        }
        await store.refreshRemote()
        phase = .idle
        lastResult = failures.isEmpty ? "已上传 \(uploaded) 张" : "已上传 \(uploaded) 张，\(failures.count) 张失败"
    }

    private func upload(_ item: PhotoItem, api: ApiClient, tier: SafetyTier) async throws {
        guard let assetID = item.localAssetID else { return }
        let photoKit = store.photoKit
        let exported = try await photoKit.exportOriginal(assetID: assetID)
        defer { try? FileManager.default.removeItem(at: exported.directory) }

        let thumbnail = try await photoKit.makeThumbnailJPEG(assetID: assetID)
        try await api.uploadThumbnail(id: exported.sha256, tier: tier, data: thumbnail)
        if let motion = exported.motionFile, let motionSHA = exported.motionSHA256 {
            try await api.uploadMotion(id: exported.sha256, tier: tier, file: motion, sha256: motionSHA)
        }
        // Last, because this request commits the photo on the server.
        try await api.uploadOriginal(OriginalUpload(
            id: exported.sha256,
            tier: tier,
            takenAt: item.takenAt,
            filename: exported.filename,
            contentType: exported.contentType,
            width: item.width,
            height: item.height,
            sourceLocalID: assetID,
            motionSize: exported.motionSize
        ), file: exported.file)
        ImageCache.shared.storeThumbnail(thumbnail, id: exported.sha256)
    }

    /// Removes local copies that a fresh NAS listing confirms. iOS asks for confirmation.
    func freeSpace() async {
        lastResult = nil
        do {
            try await store.fetchRemoteStrict()
            let targets = freeable
            guard !targets.isEmpty else { return }
            try await store.delete(targets, includingNAS: false)
            lastResult = "已从手机移除 \(targets.count) 张，原图保留在 NAS"
        } catch {
            lastResult = "未释放空间：\(error.localizedDescription)"
        }
    }
}
