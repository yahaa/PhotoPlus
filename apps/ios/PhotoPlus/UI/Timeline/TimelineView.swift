import SwiftUI

/// Photos-like rolling timeline. TODO: PhotoKit placeholders + NAS originals.
struct TimelineView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Timeline placeholder")
                        .font(.headline)
                    Text("Local PhotoKit thumbs stay on device; older originals archive to NAS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Upload queue") {
                    UploadQueueView()
                }
            }
            .navigationTitle("PhotoPlus")
        }
    }
}

#Preview {
    TimelineView()
}
