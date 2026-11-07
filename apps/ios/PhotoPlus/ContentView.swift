import SwiftUI

/// Library and Collections follow Photos; Settings is PhotoPlus's own addition.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var archive: ArchiveEngine
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("图库", systemImage: "photo.fill.on.rectangle.fill") }
            CollectionsView()
                .tabItem { Label("精选集", systemImage: "square.stack.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
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
