import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("Timeline", systemImage: "photo.on.rectangle") }
            DevicesView()
                .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
}
