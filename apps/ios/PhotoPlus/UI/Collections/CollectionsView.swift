import SwiftUI

/// The Photos Collections tab: pinned media types and My Albums, plus what's only on the NAS.
struct CollectionsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var albums: [AlbumSummary] = []

    private var userAlbums: [AlbumSummary] { albums.filter(\.isUserAlbum) }
    private var smartAlbums: [AlbumSummary] { albums.filter { !$0.isUserAlbum && $0.count > 0 } }
    private var nasOnly: [PhotoItem] { store.items.filter { $0.storage == .nasOnly } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !userAlbums.isEmpty {
                        sectionHeader("我的相簿")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(userAlbums) { album in
                                    NavigationLink(value: album) { AlbumCard(album: album) }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    sectionHeader("媒体类型")
                    LazyVStack(spacing: 0) {
                        ForEach(smartAlbums) { album in
                            NavigationLink(value: album) {
                                row(symbol: album.symbol, title: album.title, count: album.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    sectionHeader("NAS")
                    NavigationLink {
                        AlbumGridHost(title: "仅在 NAS", items: nasOnly)
                    } label: {
                        row(symbol: "externaldrive.connected.to.line.below", title: "仅在 NAS", count: nasOnly.count)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("精选集")
            .navigationDestination(for: AlbumSummary.self) { album in
                AlbumContentView(album: album)
            }
            .task(id: store.items.count) {
                let photoKit = store.photoKit
                albums = await Task.detached { photoKit.albums() }.value
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.title2.bold()).padding(.horizontal, 16)
    }

    private func row(symbol: String, title: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
            Text(title)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct AlbumCard: View {
    @EnvironmentObject private var store: LibraryStore
    let album: AlbumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let item = store.items.first(where: { $0.localAssetID == album.keyAssetID }) {
                    ThumbnailView(item: item, pixelSize: 500)
                } else {
                    Color(.secondarySystemBackground).overlay { Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(album.title).font(.subheadline).lineLimit(1)
            Text("\(album.count)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 160, alignment: .leading)
    }
}

private struct AlbumContentView: View {
    @EnvironmentObject private var store: LibraryStore
    let album: AlbumSummary
    @State private var assetIDs = Set<String>()

    var body: some View {
        AlbumGridHost(title: album.title, items: store.items.filter { $0.localAssetID.map(assetIDs.contains) ?? false })
            .task(id: store.items.count) {
                let photoKit = store.photoKit
                let albumID = album.id
                assetIDs = await Task.detached { photoKit.assetIDs(inAlbum: albumID) }.value
            }
    }
}

private struct AlbumGridHost: View {
    let title: String
    let items: [PhotoItem]
    @State private var scrollTarget: String?

    var body: some View {
        PhotoGridView(title: title, items: items, scrollTarget: $scrollTarget)
    }
}
