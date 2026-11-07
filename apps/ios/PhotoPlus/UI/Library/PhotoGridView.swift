import SwiftUI

/// The square grid. It opens at the newest photo, at the bottom, as Photos does.
struct PhotoGridView: View {
    @EnvironmentObject private var archive: ArchiveEngine
    @EnvironmentObject private var store: LibraryStore

    let title: String
    let items: [PhotoItem]
    @Binding var scrollTarget: String?
    var showsArchiveStatus = false

    @State private var columnCount = 3
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var viewerStart: PhotoItem?
    @State private var deleteTargets: [PhotoItem] = []
    @Namespace private var zoom

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount), spacing: 2) {
                    ForEach(items) { cell($0) }
                }
                footer
            }
            .defaultScrollAnchor(.bottom)
            .gesture(MagnifyGesture().onEnded { value in
                withAnimation(.snappy) { columnCount = value.magnification > 1 ? 3 : 5 }
            })
            .onChange(of: scrollTarget, initial: true) { _, target in
                guard let target else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .top)
                    scrollTarget = nil
                }
            }
        }
        .navigationTitle(isSelecting ? selectionTitle : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .fullScreenCover(item: $viewerStart) { start in
            PhotoViewer(items: items, startID: start.id)
                .zoomTransition(sourceID: start.id, namespace: zoom)
        }
        .modifier(DeleteConfirmation(targets: $deleteTargets) {
            selection = []
            isSelecting = false
        })
    }

    private func cell(_ item: PhotoItem) -> some View {
        Button {
            if isSelecting {
                toggle(item)
            } else {
                viewerStart = item
            }
        } label: {
            ThumbnailView(item: item, pixelSize: columnCount == 3 ? 400 : 240)
                .aspectRatio(1, contentMode: .fit)
                .overlay { GridCellBadges(item: item, isSelected: selection.contains(item.id), isSelecting: isSelecting) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
        .zoomSource(id: item.id, namespace: zoom)
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

    private var footer: some View {
        VStack(spacing: 2) {
            Text(PhotoFormat.summary(items)).font(.footnote.weight(.semibold))
            if showsArchiveStatus { ArchiveStatusLine() }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("grid-footer")
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelecting ? "取消" : "选择") {
                isSelecting.toggle()
                selection = []
            }
            .disabled(items.isEmpty)
        }
        if isSelecting {
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    deleteTargets = items.filter { selection.contains($0.id) }
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private var selectionTitle: String {
        selection.isEmpty ? "选择项目" : "已选择 \(selection.count) 项"
    }

    private func toggle(_ item: PhotoItem) {
        if selection.remove(item.id) == nil { selection.insert(item.id) }
    }
}

/// Badges drawn over a cell, in the corners Photos uses.
struct GridCellBadges: View {
    let item: PhotoItem
    let isSelected: Bool
    let isSelecting: Bool

    var body: some View {
        ZStack {
            if item.storage == .nasOnly {
                corner(.topTrailing) { Image(systemName: "icloud.and.arrow.down") }
            }
            if item.isFavorite {
                corner(.bottomLeading) { Image(systemName: "heart.fill") }
            }
            if item.kind == .video {
                corner(.bottomTrailing) { Text(PhotoFormat.duration(item.duration)).monospacedDigit() }
            }
            if isSelecting, isSelected {
                Color.white.opacity(0.25)
                corner(.bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.title3)
                }
            }
        }
    }

    private func corner<Content: View>(_ alignment: Alignment, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// The line under the grid where Photos reports iCloud sync, here reporting NAS archiving.
struct ArchiveStatusLine: View {
    @EnvironmentObject private var archive: ArchiveEngine
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        Group {
            if case let .uploading(done, total) = archive.phase {
                Text("正在归档到 NAS：\(done)/\(total)")
            } else if case .unreachable = store.nasState {
                Text("无法连接 NAS")
            } else if store.nasState == .connected {
                Text("NAS 已连接")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

extension View {
    /// The zoom from a grid cell into the viewer, available from iOS 18.
    @ViewBuilder func zoomSource(id: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder func zoomTransition(sourceID: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
