import SwiftUI

/// iCloud-like upload progress affordance — stub.
struct UploadQueueView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("0 items")
            Text("Waiting for PhotoKit scan + NAS API")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    UploadQueueView()
}
