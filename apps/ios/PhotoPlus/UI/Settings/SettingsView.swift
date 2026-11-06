import SwiftUI

/// Phone settings only (no admin UI).
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Rolling archive retention") {
                    Text("3 / 6 / 12 months — older originals upload to NAS, then leave the phone.")
                        .foregroundStyle(.secondary)
                }
                Section("Storage status") {
                    Text("Local free space · NAS used · upload queue — TODO wire API.")
                        .foregroundStyle(.secondary)
                }
                Section("Safety tier") {
                    Text("Casual / Important → SeaweedFS collections (replica policy).")
                        .foregroundStyle(.secondary)
                }
                Section("Account & devices") {
                    Text("Signed-in devices list lives under Devices tab for now.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
