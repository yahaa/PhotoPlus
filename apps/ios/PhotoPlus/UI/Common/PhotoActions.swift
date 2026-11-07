import SwiftUI
import UIKit

/// What the context menu, the selection menu and the viewer's menu can do to photos.
/// NAS-only photos have no PhotoKit asset, so favorite, hide and album actions need a phone copy.
@MainActor
final class PhotoActions: ObservableObject {
    @Published var shareURLs: ShareURLs?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var albumTargets: [PhotoItem] = []
    @Published var deleteTargets: [PhotoItem] = []

    func share(_ items: [PhotoItem], store: LibraryStore) {
        run {
            var urls: [URL] = []
            for item in items {
                urls.append(try await ShareFile.prepare(item, api: store.settings.apiClient))
            }
            self.shareURLs = ShareURLs(urls: urls)
        }
    }

    func copy(_ item: PhotoItem, store: LibraryStore) {
        run {
            let data: Data
            if let assetID = item.localAssetID {
                data = try await store.photoKit.imageData(assetID: assetID)
            } else if let id = item.remote?.id {
                let file = try await ImageCache.shared.originalFile(id: id, api: store.settings.apiClient)
                data = try Data(contentsOf: file)
            } else {
                throw PhotoKitError.assetGone
            }
            UIPasteboard.general.image = UIImage(data: data)
        }
    }

    func setFavorite(_ isFavorite: Bool, items: [PhotoItem], store: LibraryStore) {
        run { try await store.setFavorite(isFavorite, items: items) }
    }

    func hide(_ items: [PhotoItem], store: LibraryStore) {
        run {
            try await store.photoKit.hide(assetIDs: items.compactMap(\.localAssetID))
            await store.reloadLocal()
        }
    }

    func duplicate(_ items: [PhotoItem], store: LibraryStore) {
        run {
            for id in items.compactMap(\.localAssetID) {
                try await store.photoKit.duplicate(assetID: id)
            }
            await store.reloadLocal()
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await work()
            } catch let error as NSError where error.domain == "PHPhotosErrorDomain" && error.code == 3072 {
                // The user declined iOS's prompt; nothing changed and nothing needs saying.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ShareURLs: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// The menu rows shared by long-press and the selection and viewer menus.
struct PhotoMenuItems: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var actions: PhotoActions
    let items: [PhotoItem]
    /// Delete sits in the top row on long-press and at the end of the viewer's menu, as in Photos.
    var showsQuickRow = true

    private var localItems: [PhotoItem] { items.filter { $0.localAssetID != nil } }
    private var allFavorite: Bool { !localItems.isEmpty && localItems.allSatisfy(\.isFavorite) }
    private var images: [PhotoItem] { items.filter { $0.kind != .video } }

    var body: some View {
        if showsQuickRow {
            ControlGroup {
                Button { actions.share(items, store: store) } label: { Label("共享", systemImage: "square.and.arrow.up") }
                favoriteButton
                Button(role: .destructive) { actions.deleteTargets = items } label: { Label("删除", systemImage: "trash") }
            }
        }
        if items.count == 1, images.count == 1 {
            Button { actions.copy(items[0], store: store) } label: { Label("拷贝", systemImage: "doc.on.doc") }
        }
        if !localItems.isEmpty {
            Button { actions.duplicate(localItems.filter { $0.kind != .video }, store: store) } label: {
                Label("复制", systemImage: "plus.square.on.square")
            }
            .disabled(!localItems.contains { $0.kind != .video })
            Button { actions.hide(localItems, store: store) } label: { Label("隐藏", systemImage: "eye.slash") }
            Divider()
            Button { actions.albumTargets = localItems } label: { Label("添加到相簿", systemImage: "rectangle.stack.badge.plus") }
        }
        if !showsQuickRow {
            Divider()
            Button(role: .destructive) { actions.deleteTargets = items } label: { Label("删除", systemImage: "trash") }
        }
    }

    private var favoriteButton: some View {
        Button {
            actions.setFavorite(!allFavorite, items: localItems, store: store)
        } label: {
            Label(allFavorite ? "取消收藏" : "收藏", systemImage: allFavorite ? "heart.fill" : "heart")
        }
        .disabled(localItems.isEmpty)
    }
}

/// Presents what `PhotoActions` asks for. Delete isn't here: callers attach `DeleteConfirmation`
/// to the control it should point at.
struct PhotoActionPresenter: ViewModifier {
    @ObservedObject var actions: PhotoActions

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.shareURLs) { ActivityView(urls: $0.urls) }
            .sheet(isPresented: Binding(get: { !actions.albumTargets.isEmpty }, set: { if !$0 { actions.albumTargets = [] } })) {
                AlbumPickerSheet(targets: actions.albumTargets)
            }
            .alert("无法完成", isPresented: Binding(get: { actions.errorMessage != nil }, set: { if !$0 { actions.errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(actions.errorMessage ?? "")
            }
    }
}

/// Add to Album: an existing album or a new one.
struct AlbumPickerSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let targets: [PhotoItem]

    @State private var albums: [AlbumSummary] = []
    @State private var isNaming = false
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Button { isNaming = true } label: { Label("新建相簿", systemImage: "plus") }
                ForEach(albums) { album in
                    Button { add(to: album.id) } label: {
                        LabeledContent(album.title, value: "\(album.count)")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("添加到相簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .alert("新建相簿", isPresented: $isNaming) {
                TextField("标题", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建", action: create)
            }
            .task { await loadAlbums() }
        }
    }

    private func loadAlbums() async {
        let photoKit = store.photoKit
        albums = await Task.detached { photoKit.albums().filter(\.isUserAlbum) }.value
    }

    private func add(to albumID: String) {
        Task {
            do {
                try await store.photoKit.addAssets(targets.compactMap(\.localAssetID), toAlbum: albumID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func create() {
        let title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
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
