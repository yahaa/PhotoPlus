import AVKit
import Photos
import SwiftUI

struct PageGestures {
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void
    let onPan: (PagePan) -> Void
}

/// One step of a vertical drag on a photo.
struct PagePan {
    enum Phase {
        case began
        case changed
        case ended
    }

    let phase: Phase
    let translation: CGFloat
    var translationX: CGFloat = 0
    let velocity: CGFloat
}

/// One page: an image with zoom, or a poster that plays a local video.
struct PhotoPage: View {
    @EnvironmentObject private var settings: AppSettings
    let item: PhotoItem
    let isCurrent: Bool
    let gestures: PageGestures

    @State private var image: UIImage?
    @State private var isLoadingOriginal = false
    @State private var hasNASOriginal = false
    @State private var loadError: String?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let image {
                ZoomableImage(image: image, isCurrent: isCurrent, gestures: gestures)
                    .accessibilityIdentifier(imageIdentifier)
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

    /// `viewer-image-nas-original` exists only once the NAS's bytes have decoded, which tests rely on.
    private var imageIdentifier: String {
        if hasNASOriginal { return "viewer-image-nas-original" }
        return isLoadingOriginal ? "viewer-image-loading" : "viewer-image"
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
                if let decoded {
                    image = decoded
                    hasNASOriginal = true
                    loadError = nil
                } else {
                    loadError = "无法解码原图"
                }
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
/// The image view is sized to the photo, not the screen, so a zoomed photo can't pan past its edges.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let isCurrent: Bool
    let gestures: PageGestures

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.delegate = context.coordinator
        scrollView.addGestureRecognizer(pan)
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.gestures = gestures
        scrollView.setImage(image)
        if !isCurrent, scrollView.zoomScale > 1 { scrollView.setZoomScale(1, animated: false) }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var gestures: PageGestures?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            gestures?.onZoomChange(scale > 1.01)
        }

        @objc func singleTapped() { gestures?.onTap() }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? ZoomScrollView, let imageView = scrollView.imageView else { return }
            // The bars go as the zoom starts, not when it ends, as in Photos.
            if scrollView.zoomScale > 1.01 {
                gestures?.onZoomChange(false)
                scrollView.setZoomScale(1, animated: true)
            } else {
                gestures?.onZoomChange(true)
                scrollView.zoomToFill(around: recognizer.location(in: imageView))
            }
        }

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            let moved = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view).y
            let phase: PagePan.Phase
            switch recognizer.state {
            case .began: phase = .began
            case .changed: phase = .changed
            case .ended, .cancelled, .failed: phase = .ended
            default: return
            }
            gestures?.onPan(PagePan(phase: phase, translation: moved.y, translationX: moved.x, velocity: velocity))
        }

        /// Vertical drags at rest belong to the viewer: up opens the panel, down carries the photo away.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let scrollView = pan.view as? UIScrollView else { return true }
            let velocity = pan.velocity(in: pan.view)
            return scrollView.zoomScale <= 1.01 && abs(velocity.y) > abs(velocity.x) * 1.2
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

final class ZoomScrollView: UIScrollView {
    private(set) var imageView: UIImageView?
    private var laidOutBounds = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        maximumZoomScale = 6
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Swapping a degraded image for the full one keeps the current zoom.
    func setImage(_ image: UIImage) {
        if let imageView {
            guard imageView.image !== image else { return }
            let sameShape = abs(aspect(of: imageView.image) - aspect(of: image)) < 0.01
            imageView.image = image
            if !sameShape { fit() }
        } else {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFit
            addSubview(view)
            imageView = view
            fit()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutBounds else { return }
        laidOutBounds = bounds.size
        fit()
    }

    private func aspect(of image: UIImage?) -> CGFloat {
        guard let size = image?.size, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func fit() {
        guard let imageView, let image = imageView.image, bounds.width > 0, bounds.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        zoomScale = 1
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerContent()
    }

    func centerContent() {
        contentInset = UIEdgeInsets(
            top: max((bounds.height - contentSize.height) / 2, 0),
            left: max((bounds.width - contentSize.width) / 2, 0),
            bottom: 0,
            right: 0
        )
    }

    /// Double-tap's zoom: just enough for the photo to fill the screen.
    func zoomToFill(around point: CGPoint) {
        guard let imageView else { return }
        let size = imageView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        var scale = max(bounds.width / size.width, bounds.height / size.height)
        if scale < 1.2 { scale = 2.5 }
        let rect = CGRect(
            x: point.x - bounds.width / scale / 2,
            y: point.y - bounds.height / scale / 2,
            width: bounds.width / scale,
            height: bounds.height / scale
        )
        zoom(to: rect, animated: true)
    }
}
