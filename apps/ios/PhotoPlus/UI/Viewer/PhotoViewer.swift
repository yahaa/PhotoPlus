import SwiftUI

/// Full-screen viewer. Tap toggles the bars, double-tap fills the screen, swiping up reveals the info
/// panel, and the zoom transition itself provides swipe-down to leave.
struct PhotoViewer: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let items: [PhotoItem]
    let startID: String
    @Binding var currentID: String?

    @StateObject private var actions = PhotoActions()
    @State private var showsChrome = true
    @State private var isZoomed = false
    /// 0 is the photo alone, 1 the info panel fully open.
    @State private var infoProgress: CGFloat = 0
    @State private var isPanning = false
    @State private var panStartedOpen = false

    private var infoIsOpen: Bool { infoProgress > 0 }

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
            background.ignoresSafeArea()
            GeometryReader { geometry in
                let openHeight = pagerOpenHeight(in: geometry.size)
                VStack(spacing: 0) {
                    pager(closedHeight: geometry.size.height, openHeight: openHeight)
                        .frame(height: lerp(geometry.size.height, openHeight, infoProgress))
                    if infoIsOpen, let current {
                        PhotoInfoPanel(item: current, onPullDown: { setInfo(open: false) })
                            .frame(height: max(geometry.size.height - lerp(geometry.size.height, openHeight, infoProgress), 0))
                            .opacity(min(infoProgress * 2, 1))
                    }
                }
            }
            .ignoresSafeArea()
            if showsChrome { chrome }
        }
        .onAppear { if currentID == nil { currentID = startID } }
        .statusBarHidden(!showsChrome || infoIsOpen)
        .interactiveDismissDisabled(infoIsOpen || isZoomed)
        .modifier(PhotoActionPresenter(actions: actions))
        .onChange(of: store.items) { _, _ in
            if liveItems.isEmpty { dismiss() }
        }
    }

    private var background: Color {
        if !showsChrome { return .black }
        return infoIsOpen ? Color(.systemGroupedBackground) : Color(.systemBackground)
    }

    private func lerp(_ from: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (end - from) * progress
    }

    /// With the panel open the photo sits at the top, at full width but never over 55% of the screen.
    private func pagerOpenHeight(in size: CGSize) -> CGFloat {
        let ratio = current?.aspectRatio ?? 1
        return min(size.width / max(ratio, 0.01), size.height * 0.55)
    }

    private func pager(closedHeight: CGFloat, openHeight: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(liveItems) { item in
                    PhotoPage(
                        item: item,
                        isCurrent: item.id == currentID,
                        allowsPullDown: infoIsOpen,
                        gestures: PageGestures(
                            onTap: tapped,
                            onZoomChange: zoomChanged,
                            onPan: { panned($0, travel: closedHeight - openHeight) }
                        )
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .scrollDisabled(isPanning || infoIsOpen)
    }

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
        guard travel > 0 else { return }
        switch pan.phase {
        case .began:
            panStartedOpen = infoProgress >= 1
            isPanning = true
        case .changed:
            let start: CGFloat = panStartedOpen ? 1 : 0
            infoProgress = min(max(start - pan.translation / travel, 0), 1)
        case .ended:
            isPanning = false
            let projected = pan.translation + pan.velocity * 0.2
            setInfo(open: panStartedOpen ? projected < 80 : projected < -80)
        }
    }

    private func setInfo(open: Bool) {
        if open { showsChrome = true }
        withAnimation(.snappy) { infoProgress = open ? 1 : 0 }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 10) {
            if !infoIsOpen { topBar }
            Spacer()
            if !infoIsOpen, liveItems.count > 1 {
                ThumbnailStrip(items: liveItems, currentID: $currentID)
            }
            if let current { bottomBar(current) }
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { GlassIcon(symbol: "chevron.left") }
                .accessibilityLabel("返回")
                .accessibilityIdentifier("viewer-back")
            Spacer()
            if let current {
                VStack(spacing: 0) {
                    Text(PhotoFormat.day(current.takenAt)).font(.footnote.weight(.semibold))
                    Text(PhotoFormat.time(current.takenAt)).font(.caption2)
                }
                .padding(.horizontal, 28)
                .frame(height: 44)
                .glass(in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("viewer-date")
                Spacer()
                Menu {
                    PhotoMenuItems(actions: actions, items: [current], showsQuickRow: false)
                } label: {
                    GlassIcon(symbol: "ellipsis")
                }
                .accessibilityLabel("更多")
                .accessibilityIdentifier("viewer-more")
            }
        }
        .padding(.horizontal, 16)
    }

    private func bottomBar(_ item: PhotoItem) -> some View {
        HStack {
            Button { actions.share([item], store: store) } label: {
                if actions.isBusy {
                    ProgressView().frame(width: 44, height: 44).glass(in: Circle())
                } else {
                    GlassIcon(symbol: "square.and.arrow.up")
                }
            }
            .accessibilityLabel("分享")
            .accessibilityIdentifier("viewer-share")
            Spacer()
            HStack(spacing: 4) {
                Button {
                    actions.setFavorite(!item.isFavorite, items: [item], store: store)
                } label: {
                    barIcon(item.isFavorite ? "heart.fill" : "heart")
                }
                .disabled(item.localAssetID == nil)
                .accessibilityLabel(item.isFavorite ? "取消个人收藏" : "个人收藏")
                .accessibilityIdentifier("viewer-favorite")
                Button { setInfo(open: !infoIsOpen) } label: { barIcon(infoIsOpen ? "info.circle.fill" : "info.circle") }
                    .accessibilityLabel("信息")
                    .accessibilityIdentifier("viewer-info")
            }
            .padding(.horizontal, 6)
            .glass(in: Capsule())
            Spacer()
            Button { actions.deleteTargets = [item] } label: { GlassIcon(symbol: "trash") }
                .accessibilityLabel("删除")
                .accessibilityIdentifier("viewer-delete")
                // Attached here so the choice appears as a bubble over the bin, as in Photos.
                .modifier(DeleteConfirmation(targets: $actions.deleteTargets))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func barIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// The strip above the toolbar. The current photo sits centred, apart from its neighbours,
/// and dragging the strip moves through the photos.
struct ThumbnailStrip: View {
    let items: [PhotoItem]
    @Binding var currentID: String?

    @State private var position = ScrollPosition(idType: String.self)
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(items) { thumbnail($0) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, geometry.size.width / 2)
            }
            .scrollPosition($position, anchor: .center)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                isDragging = phase == .interacting || phase == .decelerating
            }
            .onChange(of: position.viewID(type: String.self)) { _, id in
                if isDragging, let id, id != currentID { currentID = id }
            }
            .onChange(of: currentID) { _, id in
                if !isDragging { center(id, animated: true) }
            }
            .onChange(of: geometry.size.width, initial: true) { _, _ in
                // The first layout has no width yet, so centring has to wait for the next pass.
                DispatchQueue.main.async { center(currentID, animated: false) }
            }
        }
        .frame(height: 44)
        .accessibilityIdentifier("viewer-strip")
    }

    private func thumbnail(_ item: PhotoItem) -> some View {
        let isCurrent = item.id == currentID
        return ThumbnailView(item: item, pixelSize: 120)
            .frame(width: isCurrent ? 44 : 30, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(.horizontal, isCurrent ? 8 : 0)
            .contentShape(Rectangle())
            .onTapGesture { currentID = item.id }
            .id(item.id)
    }

    private func center(_ id: String?, animated: Bool) {
        guard let id else { return }
        var transaction = Transaction(animation: animated ? .snappy(duration: 0.2) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) { position.scrollTo(id: id, anchor: .center) }
    }
}
