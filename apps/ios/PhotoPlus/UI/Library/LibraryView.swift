import SwiftUI

/// The Library: the All grid plus Years and Months, chosen from the bottom bar.
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var bar: BottomBarModel
    @State private var scrollTarget: String?
    @State private var monthTarget: String?
    @State private var yearTarget: String?

    var body: some View {
        NavigationStack {
            content
        }
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
            ZStack {
                // Stays alive under Years and Months, so All keeps its scroll position.
                PhotoGridView(title: "图库", allItems: store.items, style: .library, scrollTarget: $scrollTarget, isActive: bar.mode == .all)
                    .opacity(bar.mode == .all ? 1 : 0)
                    .allowsHitTesting(bar.mode == .all)
                if bar.mode == .months {
                    TimelineCardsView(style: .months, groups: months, target: $monthTarget) { group in
                        scrollTarget = TimelineCardsView.hero(of: group).id
                        withAnimation(.easeInOut(duration: 0.45)) { bar.mode = .all }
                    }
                    .background(Color(.systemBackground))
                } else if bar.mode == .years {
                    TimelineCardsView(style: .years, groups: years, target: $yearTarget) { group in
                        monthTarget = monthID(of: group)
                        withAnimation(.easeInOut(duration: 0.45)) { bar.mode = .months }
                    }
                    .background(Color(.systemBackground))
                }
            }
            .onChange(of: bar.mode) { old, new in
                // Coming from All, open at the period the grid was showing, as Photos does.
                guard old == .all, let anchor = bar.anchorDate else { return }
                if new == .months {
                    monthTarget = months.last { Calendar.current.isDate($0.date, equalTo: anchor, toGranularity: .month) }?.id
                } else if new == .years {
                    yearTarget = years.last { Calendar.current.isDate($0.date, equalTo: anchor, toGranularity: .year) }?.id
                }
            }
        }
    }

    private var months: [TimelineGroup] { TimelineGrouper.groups(store.items, by: [.year, .month]) }
    private var years: [TimelineGroup] { TimelineGrouper.groups(store.items, by: [.year]) }

    /// The month holding the year card's photo, so the tap lands where the finger was looking.
    private func monthID(of year: TimelineGroup) -> String? {
        let hero = TimelineCardsView.hero(of: year)
        return months.first { $0.items.contains { $0.id == hero.id } }?.id
    }
}

/// Large cards for the Years and Months views. They scroll under the status bar, with no title bar.
struct TimelineCardsView: View {
    enum Style {
        case years
        case months
    }

    let style: Style
    let groups: [TimelineGroup]
    @Binding var target: String?
    let onSelect: (TimelineGroup) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: style == .years ? 22 : 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            if style == .months {
                                Text(PhotoFormat.month(group.date)).font(.title3.bold())
                            }
                            Button { onSelect(group) } label: { card(group) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(style == .years ? "year-card" : "month-card")
                        }
                        .id(group.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .contentMargins(.top, 62, for: .scrollContent)
            .contentMargins(.bottom, BottomBarMetrics.height + 8, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            .ignoresSafeArea(edges: .top)
            .hidesScrollEdgeEffect()
            .edgeFade(.top, color: Color(.systemBackground), height: 90)
            .edgeFade(.bottom, color: .black.opacity(0.35), height: 110)
            .onChange(of: target, initial: true) { _, value in
                guard let value else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(value, anchor: .center)
                    target = nil
                }
            }
            .task { await preloadHeroes() }
        }
    }

    /// Cards crossfade in, so their photos should already be there, nearest the landing point first.
    private func preloadHeroes() async {
        let center = target.flatMap { id in groups.firstIndex { $0.id == id } } ?? groups.count - 1
        let nearest = groups.indices.sorted { abs($0 - center) < abs($1 - center) }.prefix(12)
        await ThumbnailMemory.preload(nearest.map { Self.hero(of: groups[$0]) }, pixels: Self.cardPixels)
    }

    private static let cardPixels: CGFloat = 800

    private func card(_ group: TimelineGroup) -> some View {
        let hero = Self.hero(of: group)
        return ThumbnailView(item: hero, pixelSize: Self.cardPixels)
            .frame(height: style == .years ? 270 : 240)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Text(style == .years ? PhotoFormat.year(group.date) : PhotoFormat.dayOfMonth(hero.takenAt))
                    .font(style == .years ? .title3.bold() : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(style == .years ? 18 : 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    static func hero(of group: TimelineGroup) -> PhotoItem {
        group.items.first(where: \.isFavorite) ?? group.items[group.items.count / 2]
    }
}
