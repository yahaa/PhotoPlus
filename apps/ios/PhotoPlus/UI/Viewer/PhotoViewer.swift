import AVKit
import Photos
import SwiftUI

/// Full-screen viewer: swipe between items, tap to toggle the bars, pinch or double-tap to zoom.
struct PhotoViewer: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let items: [PhotoItem]
    let startID: String

    @State private var currentID: String?
    @State private var showsChrome = true
    @State private var showsInfo = false
    @State private var deleteTargets: [PhotoItem] = []
    @State private var shareFile: ShareFile?
    @State private var isPreparingShare = false
    @State private var shareError: String?

    /// Taken from the store, so favorites and deletions show up while the viewer is open.
    private var liveItems: [PhotoItem] {
        let current = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { current[$0.id] }
    }

    private var current: PhotoItem? {
        liveItems.first { $0.id == currentID } ?? liveItems.first
    }

    var body: some View {
        ZStack {
            (showsChrome ? Color(.systemBackground) : Color.black).ignoresSafeArea()
            pager
            if showsChrome { chrome }
        }
        .onAppear { if currentID == nil { currentID = startID } }
        .statusBarHidden(!showsChrome)
        .sheet(isPresented: $showsInfo) {
            if let current { PhotoInfoSheet(item: current).presentationDetents([.medium]) }
        }
        .sheet(item: $shareFile) { ActivityView(url: $0.url) }
        .alert("无法分享", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .modifier(DeleteConfirmation(targets: $deleteTargets))
        .onChange(of: store.items) { _, _ in
            if liveItems.isEmpty { dismiss() }
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(liveItems) { item in
                    PhotoPage(item: item) { withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() } }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: { chromeIcon("chevron.left") }
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("viewer-back")
                Spacer()
                if let current {
                    VStack(spacing: 0) {
                        Text(PhotoFormat.day(current.takenAt)).font(.subheadline.weight(.semibold))
                        Text(PhotoFormat.time(current.takenAt)).font(.caption)
                    }
                }
                Spacer()
                chromeIcon("chevron.left").hidden()
            }
            Spacer()
            if let current { bottomBar(current) }
        }
        .padding(.horizontal, 16)
    }

    private func bottomBar(_ item: PhotoItem) -> some View {
        HStack {
            Button { share(item) } label: {
                if isPreparingShare { ProgressView().frame(width: 44, height: 44) } else { chromeIcon("square.and.arrow.up") }
            }
            .accessibilityLabel("分享")
            Spacer()
            Button {
                Task { await store.setFavorite(!item.isFavorite, item: item) }
            } label: {
                chromeIcon(item.isFavorite ? "heart.fill" : "heart")
            }
            .disabled(item.localAssetID == nil)
            .accessibilityLabel(item.isFavorite ? "取消个人收藏" : "个人收藏")
            Spacer()
            Button { showsInfo = true } label: { chromeIcon("info.circle") }
                .accessibilityLabel("信息")
            Spacer()
            Button { deleteTargets = [item] } label: { chromeIcon("trash") }
                .accessibilityLabel("删除")
        }
    }

    private func chromeIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
    }

    private func share(_ item: PhotoItem) {
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                shareFile = ShareFile(url: try await ShareFile.prepare(item, api: store.settings.apiClient))
            } catch {
                shareError = error.localizedDescription
            }
        }
    }
}

/// One page: an image with zoom, or a poster that plays a local video.
struct PhotoPage: View {
    @EnvironmentObject private var settings: AppSettings
    let item: PhotoItem
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var isLoadingOriginal = false
    @State private var loadError: String?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let image {
                ZoomableImage(image: image, onTap: onTap)
                    .accessibilityIdentifier(isLoadingOriginal ? "viewer-image-loading" : "viewer-image")
            }
            if item.kind == .video, player == nil {
                Button { Task { await play() } } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white, .black.opacity(0.4))
                }
                .accessibilityLabel("播放")
            }
            if isLoadingOriginal {
                ProgressView("正在从 NAS 下载原图")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("viewer-error")
            }
        }
        .task(id: item.id) { await load() }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func load() async {
        if let assetID = item.localAssetID {
            let pixels = UIScreen.main.nativeBounds.height * 2
            for await next in ImageLoader.localImages(assetID: assetID, pixels: pixels, mode: .aspectFit, allowNetwork: true) {
                image = next
            }
        } else if let id = item.remote?.id {
            image = try? await ImageCache.shared.thumbnail(id: id, api: settings.apiClient)
            isLoadingOriginal = true
            defer { isLoadingOriginal = false }
            do {
                let file = try await ImageCache.shared.originalFile(id: id, api: settings.apiClient)
                let maxPixels = Int(UIScreen.main.nativeBounds.height * 2)
                let decoded = await Task.detached { ImageCache.downsampled(file: file, maxPixels: maxPixels) }.value
                if let decoded { image = decoded }
                loadError = nil
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                loadError = "无法载入原图：\(error.localizedDescription)"
            }
        }
    }

    private func play() async {
        guard let assetID = item.localAssetID, let asset = PhotoKitStore.shared.asset(id: assetID) else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        let playerItem: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                continuation.resume(returning: playerItem)
            }
        }
        guard let playerItem else { return }
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        newPlayer.play()
    }
}

/// UIScrollView-based zoom, since nothing in SwiftUI nests zoom inside a pager cleanly.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = scrollView.bounds
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func singleTapped() { onTap() }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 2.5, animated: true)
        }
    }
}

/// A file ready for the share sheet, named as the photo was named.
struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }

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
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PhotoInfoSheet: View {
    let item: PhotoItem

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("拍摄时间", value: "\(PhotoFormat.day(item.takenAt)) \(PhotoFormat.time(item.takenAt))")
                if let remote = item.remote {
                    LabeledContent("文件名", value: remote.filename)
                    LabeledContent("大小", value: PhotoFormat.bytes(remote.sizeBytes + remote.motionSize))
                    LabeledContent("安全等级", value: remote.tier.title)
                }
                LabeledContent("尺寸", value: "\(item.width) × \(item.height)")
                LabeledContent("存储位置", value: storageText)
            }
            .navigationTitle("信息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var storageText: String {
        switch item.storage {
        case .localOnly: "仅手机"
        case .both: "手机和 NAS"
        case .nasOnly: "仅 NAS"
        }
    }
}
