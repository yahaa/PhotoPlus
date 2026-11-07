import SwiftUI

private struct ScrollFacts: Equatable {
    let offset: CGPoint
    let width: CGFloat
    let height: CGFloat
    let atNewest: Bool
    let fills: Bool

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset
        width = geometry.containerSize.width
        height = geometry.containerSize.height
        atNewest = geometry.visibleRect.maxY >= geometry.contentSize.height - 24
        fills = geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom > geometry.containerSize.height
    }
}

/// Scroll facts that change on every frame. They stay out of view state, because re-rendering the grid
/// on each is what made scrolling feel heavy on a phone.
@MainActor
private final class GridScrollTracker {
    private var items: [PhotoItem] = []
    private var indexByID: [String: Int] = [:]
    private var table: GridLayoutTable?
    private var columns = 3
    private var topRowIndex: Int?
    var offset = CGPoint.zero
    var viewportSize = CGSize.zero
    var viewportOrigin = CGPoint.zero
    /// Where the cells start inside the scrolling content, which is below an album's heading.
    var gridOrigin = CGPoint.zero

    func update(items: [PhotoItem], columns: Int) {
        self.items = items
        self.columns = columns
        indexByID = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        topRowIndex = nil
        rebuildTable()
    }

    func update(width: CGFloat) {
        guard width != viewportSize.width else { return }
        viewportSize.width = width
        rebuildTable()
    }

    private func rebuildTable() {
        guard viewportSize.width > 0 else { return }
        let ratios = columns == 1 ? items.map(\.aspectRatio) : Array(repeating: 1, count: items.count)
        table = GridLayoutTable(aspectRatios: ratios, columns: columns, width: viewportSize.width)
    }

    /// The photo at the top of the viewport, when that has changed since the last call.
    func newTopItem() -> PhotoItem? {
        guard let index = table?.index(atY: offset.y - gridOrigin.y), index != topRowIndex, items.indices.contains(index) else { return nil }
        topRowIndex = index
        return items[index]
    }

    func middleItemID() -> String? {
        guard let index = table?.index(atY: offset.y - gridOrigin.y + viewportSize.height / 2), items.indices.contains(index) else { return nil }
        return items[index].id
    }

    /// Where a cell is on screen right now, for the viewer's flight; nil if it's out of view.
    func screenFrame(of id: String) -> CGRect? {
        guard let index = indexByID[id], let table else { return nil }
        let frame = table.frame(at: index)
            .offsetBy(dx: gridOrigin.x - offset.x + viewportOrigin.x, dy: gridOrigin.y - offset.y + viewportOrigin.y)
        let viewport = CGRect(origin: viewportOrigin, size: viewportSize)
        return frame.intersects(viewport) ? frame : nil
    }
}

/// The header's changing line. Only the header observes it, so a new date doesn't redraw the grid.
@MainActor
final class GridHeaderState: ObservableObject {
    @Published var visibleDay: String?
    @Published var isAtNewest = true
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
    @StateObject private var header = GridHeaderState()
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
    /// What the cell positions depend on.
    private var layoutKey: [AnyHashable] { [items.map(\.id), density] }
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
                    guard let id, tracker.screenFrame(of: id) == nil else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
        }
        .overlay(alignment: .top) {
            if isLibrary, fillsScreen { LibraryHeaderGradient() }
        }
        .overlay(alignment: .topLeading) {
            if isLibrary {
                LibraryHeader(title: title, summary: PhotoFormat.summary(items), state: header, isOnPhotos: fillsScreen)
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
                sourceFrame: { tracker.screenFrame(of: $0) },
                onFlyingPhotoChange: { flyingPhotoID = $0 }
            )
        }
        .modifier(PhotoActionPresenter(actions: actions))
        .modifier(DeleteConfirmation(targets: $actions.deleteTargets) {
            selection = []
            isSelecting = false
        })
        .onChange(of: layoutKey, initial: true) { _, _ in
            tracker.update(items: items, columns: density.rawValue)
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
                .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .named(Self.contentSpace)).origin }, action: { tracker.gridOrigin = $0 })
                if isLibrary { ArchiveStatusLine().padding(.top, 8) }
            }
            .coordinateSpace(name: Self.contentSpace)
        }
        .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).origin }, action: { tracker.viewportOrigin = $0 })
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
        .onScrollGeometryChange(for: ScrollFacts.self, of: ScrollFacts.init) { _, facts in scrolled(facts) }
    }

    /// Runs on every frame of a scroll, so it mustn't touch anything the grid's body reads, except on rare changes.
    private func scrolled(_ facts: ScrollFacts) {
        tracker.offset = facts.offset
        tracker.viewportSize.height = facts.height
        tracker.update(width: facts.width)
        if let top = tracker.newTopItem() {
            if isLibrary { bar.anchorDate = top.takenAt }
            let day = PhotoFormat.day(top.takenAt)
            if day != header.visibleDay { header.visibleDay = day }
        }
        if facts.atNewest != header.isAtNewest { header.isAtNewest = facts.atNewest }
        if facts.fills != fillsScreen { fillsScreen = facts.fills }
        if isLibrary, isActive { bar.setAwayFromNewest(!facts.atNewest) }
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
        let anchor = tracker.middleItemID()
        // Swap at the scale the old grid reached, so the new one takes over without a jump.
        let ratio = CGFloat(density.rawValue) / CGFloat(next.rawValue)
        pinch.rebase(by: ratio)
        density = next
        if let anchor { DispatchQueue.main.async { proxy.scrollTo(anchor, anchor: .center) } }
        pinch.settle()
    }
}
