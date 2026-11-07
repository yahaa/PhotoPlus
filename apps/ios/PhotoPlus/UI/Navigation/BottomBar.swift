import SwiftUI

enum AppTab: Hashable {
    case library
    case collections
    case settings
    case search
}

enum LibraryMode: String, CaseIterable, Identifiable {
    case years
    case months
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .years: "年"
        case .months: "月"
        case .all: "全部"
        }
    }
}

enum BottomBarMetrics {
    /// Space scrolling content leaves so its last row rests above the bar.
    static let height: CGFloat = 72
}

/// State of the floating bar. It's custom because Photos' bar changes shape on rules TabView
/// can't express: it collapses only away from the newest photo and stays collapsed in Years and Months.
@MainActor
final class BottomBarModel: ObservableObject {
    @Published var tab: AppTab = .library {
        didSet {
            if oldValue != .search { previousTab = oldValue }
            isExpandedByTap = false
        }
    }
    @Published var mode: LibraryMode = .all {
        didSet { isExpandedByTap = false }
    }
    @Published private(set) var isAwayFromNewest = false
    @Published private(set) var isExpandedByTap = false
    @Published private(set) var scrollToNewestRequests = 0
    @Published private var hiders = Set<UUID>()
    private(set) var previousTab: AppTab = .library
    /// The date at the top of the All grid, so Years and Months open where the user was looking.
    var anchorDate: Date?

    var isHidden: Bool { !hiders.isEmpty || tab == .search }

    var isCollapsed: Bool {
        tab == .library && !isExpandedByTap && (mode != .all || isAwayFromNewest)
    }

    func setAwayFromNewest(_ away: Bool) {
        guard away != isAwayFromNewest else { return }
        isAwayFromNewest = away
        isExpandedByTap = false
    }

    func expand() {
        isExpandedByTap = true
    }

    func select(_ newTab: AppTab) {
        if tab == .library, newTab == .library {
            mode = .all
            scrollToNewestRequests += 1
        }
        tab = newTab
    }

    func setHidden(_ hidden: Bool, by owner: UUID) {
        if hidden { hiders.insert(owner) } else { hiders.remove(owner) }
    }
}

extension View {
    /// Hides the floating bar while this view is on screen and `active` holds.
    func hidesBottomBar(_ active: Bool = true) -> some View {
        modifier(HidesBottomBar(active: active))
    }
}

private struct HidesBottomBar: ViewModifier {
    @EnvironmentObject private var bar: BottomBarModel
    let active: Bool
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, value in bar.setHidden(value, by: owner) }
            .onDisappear { bar.setHidden(false, by: owner) }
            .onAppear { bar.setHidden(active, by: owner) }
    }
}

struct MainBottomBar: View {
    @ObservedObject var model: BottomBarModel
    @Namespace private var glass
    @Namespace private var highlight

    var body: some View {
        GlassGroup {
            HStack(spacing: 10) {
                if model.isCollapsed {
                    Button { withAnimation(.snappy) { model.expand() } } label: {
                        GlassIcon(symbol: "photo.fill.on.rectangle.fill", size: 48).foregroundStyle(.tint)
                    }
                    .glassID("tabs", in: glass)
                    .accessibilityLabel("显示标签")
                    .accessibilityIdentifier("tab-expand")
                    modePicker
                } else {
                    tabs.glassID("tabs", in: glass)
                    Spacer(minLength: 0)
                }
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { model.select(.search) }
                } label: {
                    GlassIcon(symbol: "magnifyingglass", size: 48)
                }
                    .glassID("search", in: glass)
                    .accessibilityLabel("搜索")
                    .accessibilityIdentifier("tab-search")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .animation(.snappy, value: model.isCollapsed)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton(.library, title: "图库", symbol: "photo.fill.on.rectangle.fill", identifier: "tab-library")
            tabButton(.collections, title: "精选集", symbol: "square.stack.fill", identifier: "tab-collections")
            tabButton(.settings, title: "设置", symbol: "gearshape.fill", identifier: "tab-settings")
        }
        .padding(4)
        .glass(in: Capsule(), reactsToTouch: false)
        .animation(.snappy, value: model.tab)
    }

    private func tabButton(_ tab: AppTab, title: String, symbol: String, identifier: String) -> some View {
        let isSelected = model.tab == tab
        return Button {
            // Only the highlight moves: Photos cuts between tabs' content rather than fading.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.select(tab) }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .frame(width: 72, height: 46)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background {
                if isSelected {
                    Capsule().fill(Color.primary.opacity(0.08)).matchedGeometryEffect(id: "tab", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(LibraryMode.allCases) { mode in
                let isSelected = model.mode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.45)) { model.mode = mode }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "mode", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("mode-\(mode.rawValue)")
            }
        }
        .padding(4)
        .glass(in: Capsule(), reactsToTouch: false)
    }
}
