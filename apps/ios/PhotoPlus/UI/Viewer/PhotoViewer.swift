import SwiftUI

enum ViewerGeometry {
    /// Where a photo sits when fitted to the screen.
    static func fit(_ item: PhotoItem?, in size: CGSize) -> CGRect {
        let ratio = item?.aspectRatio ?? 1
        let width = min(size.width, size.height * ratio)
        let height = width / max(ratio, 0.01)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// SwiftUI's transaction flags don't stop a full-screen cover's slide, so UIKit's animations are paused around it.
/// The timer is a backstop: leaving them off would freeze every animation in the app.
enum PresentationAnimation {
    @MainActor static func suspend() {
        UIView.setAnimationsEnabled(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { resume() }
    }

    @MainActor static func resume() {
        UIView.setAnimationsEnabled(true)
    }
}

/// Full-screen viewer. Tap toggles the bars, double-tap fills the screen, swiping up reveals the info
/// panel, and swiping down carries the photo back to its grid cell.
///
/// It draws its own transition instead of using `.zoom`: Photos flies only the photo while the grid shows
/// through behind it, where `.zoom` shrinks the whole screen as a rounded card, bars included.
struct PhotoViewer: View {
    private enum Phase {
        case opening
        case open
        case closing
    }

    private enum PanMode {
        case info
        case exit
    }

    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let items: [PhotoItem]
    let startID: String
    @Binding var currentID: String?
    /// The size the grid already has in memory, so the flying photo is there from the first frame.
    var flightPixels: CGFloat = 400
    /// Where a photo sits in the grid behind, in screen coordinates; nil when it's off screen.
    var sourceFrame: (String) -> CGRect? = { _ in nil }
    /// The cell the flying photo left or is heading for stays empty, as in Photos.
    var onFlyingPhotoChange: (String?) -> Void = { _ in }

    @StateObject private var actions = PhotoActions()
    @State private var phase = Phase.opening
    @State private var heroRect = CGRect.zero
    @State private var backdrop: Double = 0
    @State private var showsChrome = true
    @State private var isZoomed = false
    /// 0 is the photo alone, 1 the info panel fully open.
    @State private var infoProgress: CGFloat = 0
    @State private var panMode: PanMode?
    @State private var panStartedOpen = false
    @State private var exitDrag = CGSize.zero
    @State private var screenSize = CGSize.zero

    private var infoIsOpen: Bool { infoProgress > 0 }
    private var isDraggingToExit: Bool { panMode == .exit }
    private static let flightDuration = 0.33
    private static let flight = Animation.spring(duration: flightDuration, bounce: 0)

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
            background
                .overlay { Color(.systemGroupedBackground).opacity(showsChrome ? infoProgress : 0) }
                .opacity(backdrop)
                .ignoresSafeArea()
            GeometryReader { geometry in
                let openHeight = pagerOpenHeight(in: geometry.size)
                let pagerHeight = geometry.size.height + (openHeight - geometry.size.height) * infoProgress
                VStack(spacing: 0) {
                    // A photo stays centred in the pager, so it moves half as far as the pager's edge.
                    // Half the travel keeps it under the finger.
                    pager(travel: (geometry.size.height - openHeight) / 2)
                        .frame(height: pagerHeight)
                    if infoIsOpen, let current {
                        PhotoInfoPanel(item: current, onPullDown: { setInfo(open: false) })
                            .frame(height: max(geometry.size.height - pagerHeight, 0))
                            .opacity(min(infoProgress * 2, 1))
                    }
                }
                .scaleEffect(exitScale, anchor: .center)
                .offset(exitDrag)
                .opacity(phase == .open ? 1 : 0)
                if phase != .open, let current {
                    ThumbnailView(item: current, pixelSize: flightPixels)
                        .frame(width: heroRect.width, height: heroRect.height)
                        .position(x: heroRect.midX, y: heroRect.midY)
                }
                Color.clear.onAppear { start(in: geometry.size) }
            }
            .ignoresSafeArea()
            chrome
        }
        .statusBarHidden(!showsChrome || infoProgress > 0.3)
        .modifier(PhotoActionPresenter(actions: actions))
        .presentationBackground(.clear)
        .onChange(of: store.items) { _, _ in
            if liveItems.isEmpty { dismiss() }
        }
    }

    private var background: Color {
        showsChrome ? Color(.systemBackground) : .black
    }

    private var exitScale: CGFloat {
        guard screenSize.height > 0 else { return 1 }
        return 1 - min(max(exitDrag.height, 0) / screenSize.height, 1) * 0.5
    }

    /// With the panel open the photo sits at the top, at full width but never over 55% of the screen.
    private func pagerOpenHeight(in size: CGSize) -> CGFloat {
        let ratio = current?.aspectRatio ?? 1
        return min(size.width / max(ratio, 0.01), size.height * 0.55)
    }

    // MARK: Flight

    /// Without a cell to fly to (search, or a photo scrolled away), the photo just shrinks a little as it fades.
    private func destination(in size: CGSize, for id: String?) -> CGRect {
        id.flatMap(sourceFrame) ?? ViewerGeometry.fit(current, in: size).insetBy(dx: size.width * 0.1, dy: size.height * 0.05)
    }

    private func start(in size: CGSize) {
        guard screenSize == .zero else { return }
        screenSize = size
        PresentationAnimation.resume()
        if currentID == nil { currentID = startID }
        heroRect = destination(in: size, for: startID)
        onFlyingPhotoChange(startID)
        // On the next pass, so the flight starts from the cell rather than from an empty rect.
        DispatchQueue.main.async {
            withAnimation(Self.flight) {
                heroRect = ViewerGeometry.fit(current, in: size)
                backdrop = 1
            }
            afterFlight {
                phase = .open
                onFlyingPhotoChange(nil)
            }
        }
    }

    private func close() {
        let flying = ViewerGeometry.fit(current, in: screenSize)
        let scale = exitScale
        let width = flying.width * scale
        let height = flying.height * scale
        heroRect = CGRect(
            x: flying.midX - width / 2 + exitDrag.width,
            y: flying.midY - height / 2 + exitDrag.height,
            width: width,
            height: height
        )
        phase = .closing
        panMode = nil
        showsChrome = true
        onFlyingPhotoChange(currentID)
        withAnimation(Self.flight) {
            heroRect = destination(in: screenSize, for: currentID)
            backdrop = 0
        }
        afterFlight {
            onFlyingPhotoChange(nil)
            PresentationAnimation.suspend()
            dismiss()
        }
    }

    /// On a timer, not `withAnimation`'s completion: that sometimes never fired, which left the viewer
    /// stuck showing the flying thumbnail, with no paging, zoom or original.
    private func afterFlight(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flightDuration, execute: action)
    }

    // MARK: Gestures

    private func pager(travel: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(liveItems) { item in
                    PhotoPage(
                        item: item,
                        isCurrent: item.id == currentID,
                        gestures: PageGestures(
                            onTap: tapped,
                            onZoomChange: zoomChanged,
                            onPan: { panned($0, travel: travel) }
                        )
                    )
                    // Each page is wider than the screen, which leaves Photos' gap between photos while swiping.
                    .padding(.horizontal, Self.pageGap / 2)
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .padding(.horizontal, -Self.pageGap / 2)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .scrollDisabled(panMode != nil || infoIsOpen)
    }

    private static let pageGap: CGFloat = 20

    private func tapped() {
        if infoIsOpen {
            setInfo(open: false)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
        }
    }

    private func zoomChanged(_ zoomed: Bool) {
        isZoomed = zoomed
        withAnimation(.easeInOut(duration: 0.2)) { showsChrome = !zoomed }
    }

    private func panned(_ pan: PagePan, travel: CGFloat) {
        switch pan.phase {
        case .began:
            panStartedOpen = infoProgress >= 1
            panMode = panStartedOpen || pan.velocity < 0 ? .info : .exit
        case .changed:
            if panMode == .exit {
                exitDrag = CGSize(width: pan.translationX, height: max(pan.translation, 0))
                backdrop = 1 - min(max(pan.translation, 0) / (screenSize.height * 0.35), 1)
            } else if travel > 0 {
                let start: CGFloat = panStartedOpen ? 1 : 0
                infoProgress = min(max(start - pan.translation / travel, 0), 1)
            }
        case .ended:
            let mode = panMode
            panMode = nil
            let projected = pan.translation + pan.velocity * 0.2
            if mode == .exit {
                finishExitDrag(projected: projected)
            } else {
                setInfo(open: panStartedOpen ? projected < 80 : projected < -80)
            }
        }
    }

    private func finishExitDrag(projected: CGFloat) {
        if projected > 110 {
            close()
        } else {
            withAnimation(Self.flight) {
                exitDrag = .zero
                backdrop = 1
            }
        }
    }

    private func setInfo(open: Bool) {
        if open { showsChrome = true }
        withAnimation(.spring(duration: 0.28, bounce: 0)) { infoProgress = open ? 1 : 0 }
    }

    // MARK: Chrome

    /// Stays mounted and fades, blurring as it goes, because Photos dissolves its bars rather than cutting them.
    private var chrome: some View {
        let visible = showsChrome && phase != .closing && !isDraggingToExit && backdrop > 0.5
        let barsFade = max(1 - infoProgress * 3, 0)
        return VStack(spacing: 10) {
            ViewerTopBar(item: current, actions: actions, onBack: close)
                .opacity(barsFade)
                .allowsHitTesting(!infoIsOpen)
                .accessibilityHidden(infoIsOpen)
            Spacer()
            if liveItems.count > 1 {
                ThumbnailStrip(items: liveItems, currentID: $currentID)
                    .opacity(barsFade)
                    .allowsHitTesting(!infoIsOpen)
                    .accessibilityHidden(infoIsOpen)
            }
            if let current {
                ViewerBottomBar(item: current, actions: actions, infoIsOpen: infoIsOpen) { setInfo(open: !infoIsOpen) }
            }
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .blur(radius: visible ? 0 : 6)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(.easeInOut(duration: 0.17), value: visible)
        .background {
            // The bars stay in the hierarchy when hidden, so tests read their state from here.
            if !visible { Color.clear.accessibilityElement().accessibilityIdentifier("viewer-chrome-hidden") }
            if infoIsOpen { Color.clear.accessibilityElement().accessibilityIdentifier("viewer-topbar-hidden") }
        }
    }
}
