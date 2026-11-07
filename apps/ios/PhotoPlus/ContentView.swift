import SwiftUI

/// Library and Collections follow Photos; Settings is PhotoPlus's own addition.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var archive: ArchiveEngine
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bar = BottomBarModel()

    var body: some View {
        TabView(selection: $bar.tab) {
            LibraryView().tag(AppTab.library).toolbar(.hidden, for: .tabBar)
            CollectionsView().tag(AppTab.collections).toolbar(.hidden, for: .tabBar)
            SettingsView().tag(AppTab.settings).toolbar(.hidden, for: .tabBar)
            SearchView().tag(AppTab.search).toolbar(.hidden, for: .tabBar)
        }
        .overlay(alignment: .bottom) {
            if !bar.isHidden {
                MainBottomBar(model: bar)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environmentObject(bar)
        .task {
            await store.start()
            runAutoArchive()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store.hasLoaded else { return }
            Task {
                await store.reload()
                runAutoArchive()
            }
        }
    }

    private func runAutoArchive() {
        if settings.autoArchive { archive.start() }
    }
}
