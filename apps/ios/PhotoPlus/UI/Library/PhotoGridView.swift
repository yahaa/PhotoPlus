import SwiftUI

private struct ScrollFacts: Equatable {
    let atNewest: Bool
    let fills: Bool
}

/// Scroll facts that change too often to live in view state; re-rendering the grid on each would stutter.
private final class GridScrollTracker {
    var visibleIDs: [String] = []
    var dates: [String: Date] = [:]
    /// Cells in content coordinates, which scrolling doesn't change; `screenFrame` applies the scroll.
    var frames: [String: CGRect] = [:]
    var scrollOrigin = CGPoint.zero
    var viewportOrigin = CGPoint.zero

    /// Where a cell is on screen right now, for the viewer's flight.
    func screenFrame(of id: String) -> CGRect? {
        guard visibleIDs.contains(id), let frame = frames[id] else { return nil }
        return frame.offsetBy(dx: viewportOrigin.x - scrollOrigin.x, dy: viewportOrigin.y - scrollOrigin.y)
    }
}

/// The edge-to-edge grid behind the Library, albums and search results. It opens at the newest photo.
struct PhotoGridView: View {
    enum Style {
        case library
        case album
        case results
    }

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var bar: BottomBarModel
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let allItems: [PhotoItem]
    let style: Style
    @Binding var scrollTarget: String?
    var isActive = true
    var isLoading = false

    @StateObject private var actions = PhotoActions()
    @State private var density = GridDensity.three
    @State private var showsOriginalAspect = false
    @State private var filter = LibraryFilter.all
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var viewerStart: PhotoItem?
    @State private var viewerCurrentID: String?
    @State private var tracker = GridScrollTracker()
    @State private var visibleDay: String?
    @State private var isAtNewest = true
    @State private var fillsScreen = false
    @State private var isSearching = false
    @State private var query = ""
    @State private var hasOpenedAtNewest = false
    @State private var flyingPhotoID: String?
    @StateObject private var pinch = GridPinch()

    private var items: [PhotoItem] {
        let filtered = filter == .all ? allItems : allItems.filter(filter.matches)
        let tokens = LibrarySearch.tokens(of: query)
        return tokens.isEmpty ? filtered : LibrarySearch.filter(filtered, query: query)
    }

    private static let contentSpace = "grid-content"
    private var isLibrary: Bool { style == .library }
    /// The Library's title and buttons sit on darkened photos.
    private var usesDarkChrome: Bool { isLibrary && fillsScreen }
    private var selectedItems: [PhotoItem] { items.filter { selection.contains($0.id) } }

    var body: some View {
        ScrollViewReader { proxy in
            grid(proxy)
                .onChange(of: scrollTarget, initial: true) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .center)
                        scrollTarget = nil
                    }
                }
                .onChange(of: bar.scrollToNewestRequests) { _, _ in
                    guard isLibrary, let last = items.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: items.isEmpty, initial: true) { _, isEmpty in
                    // Photos usually arrive after the first layout, which the initial-offset anchor doesn't always survive.
                    guard !isEmpty, !hasOpenedAtNewest, scrollTarget == nil else { return }
                    hasOpenedAtNewest = true
                    DispatchQueue.main.async {
                        if let last = items.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: filter) { _, _ in
                    // The old offset means nothing in a different set of photos.
                    DispatchQueue.main.async {
                        if let last = items.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: viewerCurrentID) { _, id in
                    // The zoom back needs its cell on screen, and the grid should end up where the viewer did.
                    guard let id, !tracker.visibleIDs.contains(id) else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
        }
        .overlay(alignment: .top) {
            if isLibrary, fillsScreen {
                LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 165)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if isLibrary {
                let summary = PhotoFormat.summary(items)
                LibraryHeader(title: title, subtitle: isAtNewest ? summary : visibleDay ?? summary, isOnPhotos: fillsScreen)
            }
        }
        .overlay {
            if items.isEmpty, store.hasLoaded, !isLoading {
                GridEmptyState(title: title, query: query, filter: filter, isAlbum: style == .album)
            }
        }
        .overlay(alignment: .bottom) { bottomControls }
        .navigationTitle(style == .album && !items.isEmpty ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Without an item SwiftUI also drops the empty bar, and with it control over the status bar colour.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { topControls }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { topControls }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(usesDarkChrome && isActive ? .dark : colorScheme, for: .navigationBar)
        .hidesBottomBar(isSelecting && isActive)
        .fullScreenCover(item: $viewerStart) { start in
            PhotoViewer(
                items: items,
                startID: start.id,
                currentID: $viewerCurrentID,
                flightPixels: density.pixelSize,
                sourceFrame: tracker.screenFrame(of:),
                onFlyingPhotoChange: { flyingPhotoID = $0 }
            )
        }
        .modifier(PhotoActionPresenter(actions: actions))
        .modifier(DeleteConfirmation(targets: $actions.deleteTargets) {
            selection = []
            isSelecting = false
        })
        .onChange(of: allItems, initial: true) { _, new in
            tracker.dates = Dictionary(new.map { ($0.id, $0.takenAt) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private func grid(_ proxy: ScrollViewProxy) -> some View {
        PinchScaled(pinch: pinch) { scrollingGrid(proxy) }
    }

    private func scrollingGrid(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if style == .album, !items.isEmpty { AlbumHeading(title: title, summary: PhotoFormat.summary(items)) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.7), count: density.rawValue), spacing: 1.7) {
                    ForEach(items) { cell($0) }
                }
                .scrollTargetLayout()
                if isLibrary { ArchiveStatusLine().padding(.top, 8) }
            }
            .coordinateSpace(name: Self.contentSpace)
        }
        .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).origin }, action: { tracker.viewportOrigin = $0 })
        .onScrollGeometryChange(for: CGPoint.self, of: \.contentOffset) { _, offset in tracker.scrollOrigin = offset }
        .contentMargins(.top, isLibrary ? 152 : 0, for: .scrollContent)
        .contentMargins(.bottom, style == .results ? 8 : BottomBarMetrics.height, for: .scrollContent)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .defaultScrollAnchor(.top, for: .alignment)
        .ignoresSafeArea(edges: isLibrary ? .top : [])
        .hidesScrollEdgeEffect()
        .gesture(GridPinchRecognizer(
            onChange: { pinch.track(scale: $0, at: $1, limit: limit(for: $0)) },
            onEnd: { pinched($0, proxy: proxy) }
        ))
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.3) { ids in
            tracker.visibleIDs = ids
            let top = ids.first.flatMap { tracker.dates[$0] }
            if isLibrary { bar.anchorDate = top }
            let day = top.map(PhotoFormat.day)
            if day != visibleDay { visibleDay = day }
        }
        .onScrollGeometryChange(for: ScrollFacts.self) { geometry in
            ScrollFacts(
                atNewest: geometry.visibleRect.maxY >= geometry.contentSize.height - 24,
                fills: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom > geometry.containerSize.height
            )
        } action: { _, facts in
            if facts.atNewest != isAtNewest { isAtNewest = facts.atNewest }
            if facts.fills != fillsScreen { fillsScreen = facts.fills }
            if isLibrary, isActive { bar.setAwayFromNewest(!facts.atNewest) }
        }
    }

    private func cell(_ item: PhotoItem) -> some View {
        Button {
            if isSelecting {
                toggle(item)
            } else {
                viewerCurrentID = item.id
                store.noteViewed(item)
                // The viewer animates itself in, from this cell; the cover's own slide would carry it up from the bottom.
                PresentationAnimation.suspend()
                viewerStart = item
            }
        } label: {
            ThumbnailView(item: item, pixelSize: density.pixelSize, fits: showsOriginalAspect && density != .single)
                .aspectRatio(density == .single ? item.aspectRatio : 1, contentMode: .fit)
                .overlay { GridCellBadges(item: item, isSelected: selection.contains(item.id), isSelecting: isSelecting) }
                .opacity(flyingPhotoID == item.id ? 0 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(GridCellButtonStyle())
        .id(item.id)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.contentSpace)) }, action: { tracker.frames[item.id] = $0 })
        .contextMenu {
            PhotoMenuItems(actions: actions, items: [item])
        } preview: {
            ThumbnailView(item: item, pixelSize: 1000)
                .aspectRatio(item.aspectRatio, contentMode: .fit)
                .frame(width: 360)
                .environmentObject(store.settings)
        }
        .accessibilityIdentifier("cell-\(item.storageTag)")
        .accessibilityLabel(PhotoFormat.day(item.takenAt))
    }

    // MARK: Header

    // MARK: Bars

    @ViewBuilder private var topControls: some View {
        if isActive, style != .results { GridTopControls(
            showsFilter: isLibrary,
            isSelecting: isSelecting,
            canSelect: !items.isEmpty,
            hasSelection: !selection.isEmpty,
            filter: $filter,
            showsOriginalAspect: $showsOriginalAspect,
            onSelect: { isSelecting = true },
            onClose: endSelecting
        ) {
            PhotoMenuItems(actions: actions, items: selectedItems, showsQuickRow: false)
        }
        .environment(\.colorScheme, usesDarkChrome ? .dark : colorScheme)
        .darkGlass(usesDarkChrome) }
    }

    @ViewBuilder private var bottomControls: some View {
        if isSelecting {
            SelectionBar(count: selection.count) {
                actions.share(selectedItems, store: store)
            } onDelete: {
                actions.deleteTargets = selectedItems
            }
        } else if style == .album {
            AlbumBottomBar(isSearching: $isSearching, query: $query, filter: $filter, showsOriginalAspect: $showsOriginalAspect)
        }
    }

    // MARK: Actions

    private func toggle(_ item: PhotoItem) {
        if selection.remove(item.id) == nil { selection.insert(item.id) }
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }

    /// How far the grid may scale before the next density would be showing.
    private func limit(for scale: CGFloat) -> CGFloat {
        let next = scale >= 1 ? density.sparser : density.denser
        return CGFloat(density.rawValue) / CGFloat(next.rawValue)
    }

    private func pinched(_ scale: CGFloat, proxy: ScrollViewProxy) {
        let next = scale > 1.15 ? density.sparser : (scale < 0.87 ? density.denser : density)
        guard next != density else {
            pinch.settle()
            return
        }
        let anchor = tracker.visibleIDs.dropFirst(tracker.visibleIDs.count / 2).first
        // Swap at the scale the old grid reached, so the new one takes over without a jump.
        let ratio = CGFloat(density.rawValue) / CGFloat(next.rawValue)
        pinch.rebase(by: ratio)
        density = next
        if let anchor { DispatchQueue.main.async { proxy.scrollTo(anchor, anchor: .center) } }
        pinch.settle()
    }
}
