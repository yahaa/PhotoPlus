import Photos
import SwiftUI

/// The Photos library: an All grid plus Years and Months, switched at the bottom.
struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case years = "年"
        case months = "月"
        case all = "全部"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: LibraryStore
    @State private var mode: Mode = .all
    @State private var scrollTarget: String?

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsModePicker { modePicker }
                }
        }
    }

    private var showsModePicker: Bool {
        !store.items.isEmpty
    }

    @ViewBuilder private var content: some View {
        if store.authorization == .denied || store.authorization == .restricted {
            ContentUnavailableView {
                Label("无法访问照片", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("请在系统设置中允许 PhotoPlus 访问照片。")
            } actions: {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } else if store.hasLoaded, store.items.isEmpty {
            ContentUnavailableView("没有照片", systemImage: "photo.on.rectangle", description: Text("拍摄的照片会显示在这里。"))
        } else {
            switch mode {
            case .all:
                PhotoGridView(title: "图库", items: store.items, scrollTarget: $scrollTarget, showsArchiveStatus: true)
            case .months:
                TimelineCardsView(title: "月", groups: TimelineGrouper.groups(store.items, by: [.year, .month]), label: PhotoFormat.month) { group in
                    scrollTarget = group.items.first?.id
                    mode = .all
                }
            case .years:
                TimelineCardsView(title: "年", groups: TimelineGrouper.groups(store.items, by: [.year]), label: PhotoFormat.year) { _ in
                    mode = .months
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("视图", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .padding(.vertical, 8)
        .accessibilityIdentifier("library-mode")
    }
}

/// Large cards for the Years and Months views.
struct TimelineCardsView: View {
    let title: String
    let groups: [TimelineGroup]
    let label: (Date) -> String
    let onSelect: (TimelineGroup) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(groups) { group in
                    Button { onSelect(group) } label: { card(group) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.bottom)
        .navigationTitle(title)
    }

    private func card(_ group: TimelineGroup) -> some View {
        ThumbnailView(item: hero(of: group), pixelSize: 1000)
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(group.date)).font(.title2.bold())
                    Text(PhotoFormat.summary(group.items)).font(.footnote)
                }
                .foregroundStyle(.white)
                .shadow(radius: 4)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hero(of group: TimelineGroup) -> PhotoItem {
        group.items.first(where: \.isFavorite) ?? group.items[group.items.count / 2]
    }
}
