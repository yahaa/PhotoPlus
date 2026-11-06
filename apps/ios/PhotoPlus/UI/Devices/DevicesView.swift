import SwiftUI

/// Multi-device login under one account — list / remove stubs.
struct DevicesView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("No devices yet")
                    .font(.headline)
                Text("After sign-in, this phone and siblings appear here. Finish uploads before switching phones.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Devices")
        }
    }
}

#Preview {
    DevicesView()
}
