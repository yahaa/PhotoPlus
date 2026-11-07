import SwiftUI

/// A screen Collections pushes.
enum CollectionRoute: Hashable {
    case album(AlbumSummary)
    case filter(LibraryFilter)
    case day(Date)
}

/// The Collections tab: collapsible sections, as in Photos. Memories, People & Pets, Featured Photos
/// and Trips are missing because PhotoKit has no public API for them.
struct CollectionsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var albums: [AlbumSummary] = []
    @State private var collapsed = Set<String>()
    @State private var isNaming = false
    @State private var newAlbumName = ""
    @State private var errorMessage: String?

    private var userAlbums: [AlbumSummary] { albums.filter(\.isUserAlbum) }
    private var smartAlbums: [AlbumSummary] { albums.filter { !$0.isUserAlbum && $0.count > 0 } }
    private var pinnedFilters: [LibraryFilter] { [.favorites, .videos, .screenshots, .nasOnly, .phoneOnly] }

    private var recentDays: [TimelineGroup] {
        Array(TimelineGrouper.groups(store.items, by: [.year, .month, .day]).suffix(12).reversed())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("固定") { pinned }
                    section("相簿", trailing: { createAlbumButton }) { albumsContent }
                    if !smartAlbums.isEmpty {
                        section("媒体类型") { mediaTypes }
                    }
                    if !recentDays.isEmpty {
                        section("最近的日子") { days }
                    }
                }
                .padding(.vertical, 8)
            }
            .contentMargins(.bottom, BottomBarMetrics.height, for: .scrollContent)
            .edgeFade(.bottom, color: Color(.systemBackground), height: 100)
            .navigationTitle("精选集")
            .navigationDestination(for: CollectionRoute.self) { route in
                CollectionRouteView(route: route).hidesBottomBar()
            }
            .task(id: store.items.count) { await loadAlbums() }
            .alert("新建相簿", isPresented: $isNaming) {
                TextField("标题", text: $newAlbumName)
                Button("取消", role: .cancel) {}
                Button("创建", action: createAlbum)
            }
            .alert("无法创建相簿", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private func section<Trailing: View, Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCollapsed = collapsed.contains(title)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title).font(.title3.bold())
                Spacer()
                trailing()
                Button {
                    withAnimation(.snappy) {
                        if collapsed.remove(title) == nil { collapsed.insert(title) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                        .rotationEffect(isCollapsed ? .degrees(-90) : .zero)
                        .frame(width: 26, height: 26)
                        .background(Color(.systemGray6), in: Circle())
                }
                .accessibilityLabel(isCollapsed ? "展开\(title)" : "折叠\(title)")
                .accessibilityIdentifier("section-toggle-\(title)")
            }
            .padding(.horizontal, 16)
            if !isCollapsed { content() }
        }
    }

    private var pinned: some View {
        horizontalCards {
            ForEach(pinnedFilters) { filter in
                let matching = store.items.filter(filter.matches)
                NavigationLink(value: CollectionRoute.filter(filter)) {
                    CollectionCard(title: filter.title, cover: matching.last, symbol: filter.symbol, count: matching.count)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pinned-\(filter.rawValue)")
            }
        }
    }

    private var createAlbumButton: some View {
        Button("创建") { isNaming = true }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(.systemGray6), in: Capsule())
            .accessibilityIdentifier("create-album")
    }

    @ViewBuilder private var albumsContent: some View {
        if userAlbums.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("无可用相簿").font(.subheadline.weight(.medium))
                Text("创建的相簿将在此处显示。").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        } else {
            horizontalCards {
                ForEach(userAlbums) { album in
                    NavigationLink(value: CollectionRoute.album(album)) {
                        CollectionCard(
                            title: album.title,
                            cover: store.items.first { $0.localAssetID == album.keyAssetID },
                            symbol: "rectangle.stack",
                            count: album.count
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("album-card")
                }
            }
        }
    }

    private var mediaTypes: some View {
        LazyVStack(spacing: 0) {
            ForEach(smartAlbums) { album in
                NavigationLink(value: CollectionRoute.album(album)) {
                    HStack(spacing: 12) {
                        Image(systemName: album.symbol).frame(width: 28).foregroundStyle(.tint)
                        Text(album.title)
                        Spacer()
                        Text("\(album.count)").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var days: some View {
        horizontalCards {
            ForEach(recentDays) { group in
                NavigationLink(value: CollectionRoute.day(group.date)) {
                    CollectionCard(title: PhotoFormat.day(group.date), cover: TimelineCardsView.hero(of: group), symbol: "calendar", count: group.items.count)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func horizontalCards<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) { content() }
                .padding(.horizontal, 16)
        }
    }

    // MARK: Albums

    private func loadAlbums() async {
        let photoKit = store.photoKit
        albums = await Task.detached { photoKit.albums() }.value
    }

    private func createAlbum() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAlbumName = ""
        guard !title.isEmpty else { return }
        Task {
            do {
                try await store.photoKit.createAlbum(title: title)
                await loadAlbums()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A rounded card with its title over the cover, as in Photos' Pinned row.
struct CollectionCard: View {
    let title: String
    let cover: PhotoItem?
    let symbol: String
    var count: Int?

    var body: some View {
        Group {
            if let cover {
                ThumbnailView(item: cover, pixelSize: 500)
            } else {
                LinearGradient(colors: [Color(.systemGray4), Color(.systemGray2)], startPoint: .top, endPoint: .bottom)
                    .overlay { Image(systemName: symbol).font(.title).foregroundStyle(.white) }
            }
        }
        .frame(width: 130, height: 150)
        .overlay {
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.footnote.weight(.semibold)).lineLimit(2)
                if let count { Text("\(count)").font(.caption2) }
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// An album or a pinned collection, shown as a grid.
struct CollectionRouteView: View {
    @EnvironmentObject private var store: LibraryStore
    let route: CollectionRoute
    @State private var albumAssetIDs = Set<String>()
    @State private var scrollTarget: String?
    @State private var isLoadingAlbum = true

    var body: some View {
        PhotoGridView(title: title, allItems: items, style: .album, scrollTarget: $scrollTarget, isLoading: isLoadingAlbum)
            .task(id: store.items.count) {
                defer { isLoadingAlbum = false }
                guard case let .album(album) = route else { return }
                let photoKit = store.photoKit
                let albumID = album.id
                albumAssetIDs = await Task.detached { photoKit.assetIDs(inAlbum: albumID) }.value
            }
    }

    private var title: String {
        switch route {
        case let .album(album): album.title
        case let .filter(filter): filter.title
        case let .day(date): PhotoFormat.day(date)
        }
    }

    private var items: [PhotoItem] {
        switch route {
        case .album:
            store.items.filter { $0.localAssetID.map(albumAssetIDs.contains) ?? false }
        case let .filter(filter):
            store.items.filter(filter.matches)
        case let .day(date):
            store.items.filter { Calendar.current.isDate($0.takenAt, inSameDayAs: date) }
        }
    }
}
