import SwiftUI

/// What a grid shows when nothing matches.
struct GridEmptyState: View {
    let title: String
    let query: String
    let filter: LibraryFilter
    let isAlbum: Bool

    var body: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if filter != .all {
            ContentUnavailableView("没有符合筛选条件的项目", systemImage: filter.symbol)
        } else if isAlbum {
            EmptyAlbumHero(title: title)
        }
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
                Color.white.opacity(0.3)
                corner(.bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.title3)
                }
                .accessibilityIdentifier("cell-selected")
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

/// Under the grid, where Photos reports sync. It says nothing while all is well.
struct ArchiveStatusLine: View {
    @EnvironmentObject private var archive: ArchiveEngine
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        Group {
            if case let .uploading(done, total) = archive.phase {
                Text("正在归档到 NAS：\(done)/\(total)")
            } else if case .unreachable = store.nasState {
                Text("无法连接 NAS")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("archive-status")
    }
}

/// The search field Photos keeps at the bottom, above the keyboard.
struct BottomSearchField: View {
    @Binding var text: String
    let placeholder: String
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        GlassGroup {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("search-field")
                    if !text.isEmpty {
                        Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("清除")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .glass(in: Capsule())
                Button(action: onClose) { GlassIcon(symbol: "xmark", size: 48) }
                    .accessibilityLabel("关闭搜索")
                    .accessibilityIdentifier("search-close")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .task { isFocused = true }
    }
}

/// The sort and filter menu. Only capture-date order exists: PhotoKit can't sort by date added.
struct GridFilterMenu: View {
    @Binding var filter: LibraryFilter
    @Binding var showsOriginalAspect: Bool
    /// False when it shares a capsule with another button.
    var hasOwnGlass = true
    var size: CGFloat = 44

    var body: some View {
        Menu {
            Section {
                Label("按拍摄日期排序", systemImage: "checkmark")
            }
            Menu {
                Picker("筛选", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease")
                if filter != .all { Text(filter.title) }
            }
            if filter != .all {
                Button { filter = .all } label: { Label("移除筛选条件", systemImage: "minus.circle") }
                    .accessibilityIdentifier("filter-remove")
            }
            Menu("显示选项") {
                Toggle(isOn: $showsOriginalAspect) { Label("原始比例网格", systemImage: "aspectratio") }
            }
        } label: {
            label
        }
        .accessibilityLabel("排序与筛选")
        .accessibilityIdentifier("filter-menu")
    }

    @ViewBuilder private var label: some View {
        let icon = Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: size * 0.42, weight: .medium))
            .frame(width: size, height: size)
            .contentShape(Circle())
        if filter != .all {
            icon.foregroundStyle(.white).background(.blue, in: Circle())
        } else if hasOwnGlass {
            icon.foregroundStyle(.primary).glass(in: Circle())
        } else {
            icon.foregroundStyle(.primary)
        }
    }
}

/// The grid's top-right buttons. They carry their own glass because iOS 26's shared toolbar
/// background merges them into one capsule, where Photos keeps them separate.
struct GridTopControls<MoreMenu: View>: View {
    @Environment(\.usesDarkGlass) private var isDark
    let showsFilter: Bool
    let isSelecting: Bool
    let canSelect: Bool
    let hasSelection: Bool
    @Binding var filter: LibraryFilter
    @Binding var showsOriginalAspect: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @ViewBuilder let moreMenu: () -> MoreMenu

    var body: some View {
        HStack(spacing: 8) {
            if isSelecting {
                HStack(spacing: 0) {
                    if showsFilter {
                        GridFilterMenu(filter: $filter, showsOriginalAspect: $showsOriginalAspect, hasOwnGlass: false)
                    }
                    Menu(content: moreMenu) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .disabled(!hasSelection)
                    .accessibilityLabel("更多")
                    .accessibilityIdentifier("selection-more")
                }
                .glass(in: Capsule(), reactsToTouch: false)
                Button(action: onClose) { GlassIcon(symbol: "xmark") }
                    .accessibilityLabel("取消")
                    .accessibilityIdentifier("selection-close")
            } else {
                if showsFilter {
                    GridFilterMenu(filter: $filter, showsOriginalAspect: $showsOriginalAspect)
                }
                Button(action: onSelect) {
                    Text("选择")
                        .font(.subheadline.weight(.medium))
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(Capsule())
                        .glass(in: Capsule())
                }
                .disabled(!canSelect)
                .opacity(canSelect ? 1 : 0.4)
                .accessibilityIdentifier("select-button")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDark ? Color.white : Color.primary)
    }
}

/// Replaces the tab bar while selecting.
struct SelectionBar: View {
    let count: Int
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onShare) { GlassIcon(symbol: "square.and.arrow.up") }
                .accessibilityLabel("分享")
                .accessibilityIdentifier("selection-share")
                .disabled(count == 0)
            Spacer()
            Text(count == 0 ? "选择项目" : "已选择 \(count) 张照片")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("selection-title")
            Spacer()
            Button(action: onDelete) { GlassIcon(symbol: "trash") }
                .accessibilityLabel("删除")
                .accessibilityIdentifier("selection-delete")
                .disabled(count == 0)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background { Color(.systemBackground).ignoresSafeArea() }
    }
}

/// An album's bottom bar: filter on the left, and a search button that becomes a field.
struct AlbumBottomBar: View {
    @Binding var isSearching: Bool
    @Binding var query: String
    @Binding var filter: LibraryFilter
    @Binding var showsOriginalAspect: Bool

    var body: some View {
        Group {
            if isSearching {
                BottomSearchField(text: $query, placeholder: "搜索此相簿") {
                    isSearching = false
                    query = ""
                }
            } else {
                HStack {
                    GridFilterMenu(filter: $filter, showsOriginalAspect: $showsOriginalAspect, size: 48)
                    Spacer()
                    Button { isSearching = true } label: { GlassIcon(symbol: "magnifyingglass", size: 48) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("搜索")
                        .accessibilityIdentifier("album-search")
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 2)
    }
}

/// An empty album: a grey header carrying the title, and a note under it.
struct EmptyAlbumHero: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Color(.systemGray3)
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.largeTitle.bold())
                        Text("0 个项目").font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .containerRelativeFrame(.vertical) { height, _ in height * 0.48 }
            Spacer()
            VStack(spacing: 6) {
                Text("无照片或视频").font(.headline)
                Text("拍摄或添加的照片和视频将在此处显示。").font(.footnote).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("empty-album")
    }
}

/// Darkens the photos under the Library's title and buttons.
struct LibraryHeaderGradient: View {
    var body: some View {
        LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 165)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// The Library's title and its line of context, white over the darkened photos when there are any under it.
struct LibraryHeader: View {
    let title: String
    let summary: String
    @ObservedObject var state: GridHeaderState
    let isOnPhotos: Bool

    private var subtitle: String {
        state.isAtNewest ? summary : state.visibleDay ?? summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
                .accessibilityIdentifier("library-subtitle")
        }
        .foregroundStyle(isOnPhotos ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The navigation bar is transparent, so the title shares a line with its buttons.
        .padding(.top, -54)
        .allowsHitTesting(false)
    }
}

/// An album's title, inside the scrolling content.
struct AlbumHeading: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.largeTitle.bold())
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
