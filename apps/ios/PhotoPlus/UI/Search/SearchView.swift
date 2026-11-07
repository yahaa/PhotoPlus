import SwiftUI

/// Search, with its field at the bottom. It matches dates, filenames, media types and album titles;
/// Photos' search for people, objects and places has no public API.
struct SearchView: View {
    private enum Scope: Hashable {
        case photos
        case collections
    }

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var bar: BottomBarModel
    @State private var query = ""
    @State private var scope = Scope.photos
    @State private var albums: [AlbumSummary] = []
    @State private var scrollTarget: String?
    @State private var viewerStart: PhotoItem?
    @State private var viewerCurrentID: String?

    private var photos: [PhotoItem] { LibrarySearch.filter(store.items, query: query) }

    private var matchingAlbums: [AlbumSummary] {
        let tokens = LibrarySearch.tokens(of: query)
        guard !tokens.isEmpty else { return [] }
        return albums.filter { album in tokens.allSatisfy { album.title.lowercased().contains($0) } }
    }

    private var recents: [PhotoItem] {
        let byID = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return store.recentlyViewedIDs.compactMap { byID[$0] }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("搜索").font(.largeTitle.bold())
                    Text("可按日期、文件名、媒体类型和相簿搜索").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    recentsContent
                } else {
                    results
                }
                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom) {
                if bar.tab == .search {
                    BottomSearchField(text: $query, placeholder: "搜索你的图库…") {
                        query = ""
                        bar.tab = bar.previousTab
                    }
                    .padding(.bottom, 6)
                }
            }
            .navigationDestination(for: CollectionRoute.self) { route in
                CollectionRouteView(route: route)
            }
            .task(id: store.items.count) {
                let photoKit = store.photoKit
                albums = await Task.detached { photoKit.albums() }.value
            }
            .fullScreenCover(item: $viewerStart) { start in
                PhotoViewer(items: recents, startID: start.id, currentID: $viewerCurrentID)
            }
        }
    }

    @ViewBuilder private var recentsContent: some View {
        if !recents.isEmpty {
            Text("最近查看").font(.headline).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(recents) { item in
                        Button {
                            viewerCurrentID = item.id
                            PresentationAnimation.suspend()
                            viewerStart = item
                        } label: {
                            CollectionCard(title: PhotoFormat.day(item.takenAt), cover: item, symbol: "photo")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recent-card")
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 150)
        }
    }

    @ViewBuilder private var results: some View {
        Picker("范围", selection: $scope) {
            Text("照片 (\(photos.count))").tag(Scope.photos)
            Text("精选集 (\(matchingAlbums.count))").tag(Scope.collections)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("search-scope")
        switch scope {
        case .photos where photos.isEmpty, .collections where matchingAlbums.isEmpty:
            ContentUnavailableView("无结果", systemImage: "magnifyingglass", description: Text("换个日期、文件名或类型试试。"))
                .accessibilityIdentifier("search-empty")
        case .photos:
            PhotoGridView(title: "", allItems: photos, style: .results, scrollTarget: $scrollTarget)
        case .collections:
            List(matchingAlbums) { album in
                NavigationLink(value: CollectionRoute.album(album)) {
                    LabeledContent(album.title, value: "\(album.count)")
                }
            }
            .listStyle(.plain)
        }
    }
}
