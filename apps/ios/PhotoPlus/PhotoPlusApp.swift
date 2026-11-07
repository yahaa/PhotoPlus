import SwiftUI

@main
struct PhotoPlusApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: LibraryStore
    @StateObject private var archive: ArchiveEngine

    init() {
        let settings = AppSettings()
        let store = LibraryStore(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        _archive = StateObject(wrappedValue: ArchiveEngine(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(archive)
        }
    }
}
