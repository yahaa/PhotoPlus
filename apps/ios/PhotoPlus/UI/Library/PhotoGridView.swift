import SwiftUI

/// Scroll facts that change too often to live in view state; re-rendering the grid on each would stutter.
private final class GridScrollTracker {
    var visibleIDs: [String] = []
    var dates: [String: Date] = [:]
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
    @Namespace private var zoom

    private var items: [PhotoItem] {
        let filtered = filter == .all ? allItems : allItems.filter(filter.matches)
        let tokens = LibrarySearch.tokens(of: query)
        return tokens.isEmpty ? filtered : LibrarySearch.filter(filtered, query: query)
    }

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
                        proxy.scrollTo(target, anchor: .top)
                        scrollTarget = nil
                    }
                }
                .onChange(of: bar.scrollToNewestRequests) { _, _ in
                    guard isLibrary, let last = items.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
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
        .overlay(alignment: .topLeading) { if isLibrary { libraryHeader } }
        .overlay { emptyState }
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
            PhotoViewer(items: items, startID: start.id, currentID: $viewerCurrentID)
                .navigationTransition(.zoom(sourceID: viewerCurrentID ?? start.id, in: zoom))
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
        ScrollView {
            VStack(spacing: 0) {
                if style == .album, !items.isEmpty { AlbumHeading(title: title, summary: PhotoFormat.summary(items)) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.7), count: density.rawValue), spacing: 1.7) {
                    ForEach(items) { cell($0) }
                }
                .scrollTargetLayout()
                if isLibrary { ArchiveStatusLine().padding(.top, 8) }
            }
        }
        .contentMargins(.top, isLibrary ? 112 : 0, for: .scrollContent)
        .contentMargins(.bottom, style == .results ? 8 : BottomBarMetrics.height, for: .scrollContent)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .defaultScrollAnchor(.top, for: .alignment)
        .ignoresSafeArea(edges: isLibrary ? .top : [])
        .hidesScrollEdgeEffect()
        .simultaneousGesture(MagnifyGesture().onEnded { pinched($0.magnification, proxy: proxy) })
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.3) { ids in
            tracker.visibleIDs = ids
            let day = ids.first.flatMap { tracker.dates[$0] }.map(PhotoFormat.day)
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

    private struct ScrollFacts: Equatable {
        let atNewest: Bool
        let fills: Bool
    }

    private func cell(_ item: PhotoItem) -> some View {
        Button {
            if isSelecting {
                toggle(item)
            } else {
                viewerCurrentID = item.id
                viewerStart = item
                store.noteViewed(item)
            }
        } label: {
            ThumbnailView(item: item, pixelSize: density.pixelSize, fits: showsOriginalAspect && density != .single)
                .aspectRatio(density == .single ? item.aspectRatio : 1, contentMode: .fit)
                .overlay { GridCellBadges(item: item, isSelected: selection.contains(item.id), isSelecting: isSelecting) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
        .matchedTransitionSource(id: item.id, in: zoom)
        .contextMenu {
            PhotoMenuItems(actions: actions, items: [item])
        } preview: {
            ThumbnailView(item: item, pixelSize: 1000)
                .aspectRatio(item.aspectRatio, contentMode: .fit)
                .frame(width: 360)
                .environmentObject(store.settings)
        }
        .accessibilityIdentifier("cell-\(storageTag(item))")
        .accessibilityLabel(PhotoFormat.day(item.takenAt))
    }

    private func storageTag(_ item: PhotoItem) -> String {
        switch item.storage {
        case .localOnly: "local"
        case .both: "both"
        case .nasOnly: "nas"
        }
    }

    // MARK: Header

    private var subtitle: String {
        if isAtNewest || visibleDay == nil { return PhotoFormat.summary(items) }
        return visibleDay ?? ""
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
                .accessibilityIdentifier("library-subtitle")
        }
        .foregroundStyle(fillsScreen ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The navigation bar is transparent, so the title shares a line with its buttons.
        .padding(.top, -54)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var emptyState: some View {
        if items.isEmpty, store.hasLoaded, !isLoading {
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if filter != .all {
                ContentUnavailableView("没有符合筛选条件的项目", systemImage: filter.symbol)
            } else if style == .album {
                EmptyAlbumHero(title: title)
            }
        }
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

    private func pinched(_ magnification: CGFloat, proxy: ScrollViewProxy) {
        let next: GridDensity
        if magnification > 1.15 {
            next = density.sparser
        } else if magnification < 0.87 {
            next = density.denser
        } else {
            return
        }
        guard next != density else { return }
        let anchor = tracker.visibleIDs.dropFirst(tracker.visibleIDs.count / 2).first
        withAnimation(.snappy) { density = next }
        if let anchor {
            DispatchQueue.main.async { proxy.scrollTo(anchor, anchor: .center) }
        }
    }
}
