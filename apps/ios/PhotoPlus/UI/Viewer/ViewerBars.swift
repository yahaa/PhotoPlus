import SwiftUI

/// Back, the date capsule and the viewer's menu.
struct ViewerTopBar: View {
    let item: PhotoItem?
    @ObservedObject var actions: PhotoActions
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) { GlassIcon(symbol: "chevron.left") }
                .accessibilityLabel("返回")
                .accessibilityIdentifier("viewer-back")
            Spacer()
            if let item {
                VStack(spacing: 0) {
                    Text(PhotoFormat.day(item.takenAt)).font(.footnote.weight(.semibold))
                    Text(PhotoFormat.time(item.takenAt)).font(.caption2)
                }
                .padding(.horizontal, 28)
                .frame(height: 44)
                .glass(in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("viewer-date")
                Spacer()
                Menu {
                    PhotoMenuItems(actions: actions, items: [item], showsQuickRow: false)
                } label: {
                    GlassIcon(symbol: "ellipsis")
                }
                .accessibilityLabel("更多")
                .accessibilityIdentifier("viewer-more")
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Share, the favorite and info capsule, and delete.
struct ViewerBottomBar: View {
    @EnvironmentObject private var store: LibraryStore
    let item: PhotoItem
    @ObservedObject var actions: PhotoActions
    let infoIsOpen: Bool
    let onInfo: () -> Void

    var body: some View {
        HStack {
            Button { actions.share([item], store: store) } label: {
                if actions.isBusy {
                    ProgressView().frame(width: 44, height: 44).glass(in: Circle())
                } else {
                    GlassIcon(symbol: "square.and.arrow.up")
                }
            }
            .accessibilityLabel("分享")
            .accessibilityIdentifier("viewer-share")
            Spacer()
            HStack(spacing: 4) {
                Button {
                    actions.setFavorite(!item.isFavorite, items: [item], store: store)
                } label: {
                    barIcon(item.isFavorite ? "heart.fill" : "heart")
                }
                .disabled(item.localAssetID == nil)
                .accessibilityLabel(item.isFavorite ? "取消个人收藏" : "个人收藏")
                .accessibilityIdentifier("viewer-favorite")
                Button(action: onInfo) { barIcon(infoIsOpen ? "info.circle.fill" : "info.circle") }
                    .accessibilityLabel("信息")
                    .accessibilityIdentifier("viewer-info")
            }
            .padding(.horizontal, 6)
            .glass(in: Capsule(), reactsToTouch: false)
            Spacer()
            Button { actions.deleteTargets = [item] } label: { GlassIcon(symbol: "trash") }
                .accessibilityLabel("删除")
                .accessibilityIdentifier("viewer-delete")
                // Attached here so the choice appears as a bubble over the bin, as in Photos.
                .modifier(DeleteConfirmation(targets: $actions.deleteTargets))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func barIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
