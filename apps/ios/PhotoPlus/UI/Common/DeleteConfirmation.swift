import SwiftUI

/// Delete flow shared by the grid and the viewer. Items with a NAS copy ask whether the NAS
/// copy goes too; phone deletions then get iOS's own confirmation on top.
struct DeleteConfirmation: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @Binding var targets: [PhotoItem]
    var onDeleted: () -> Void = {}

    @State private var errorMessage: String?

    private var isPresented: Binding<Bool> {
        Binding(get: { needsChoice }, set: { if !$0 { targets = [] } })
    }

    private var needsChoice: Bool {
        targets.contains { $0.remote != nil }
    }

    private var hasLocal: Bool {
        targets.contains { $0.localAssetID != nil }
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
                if hasLocal {
                    Button("仅从手机移除") { perform(includingNAS: false) }
                    Button("从手机和 NAS 删除", role: .destructive) { perform(includingNAS: true) }
                } else {
                    Button("从 NAS 永久删除", role: .destructive) { perform(includingNAS: true) }
                }
                Button("取消", role: .cancel) { targets = [] }
            }
            .onChange(of: targets) { _, new in
                // Phone-only items have no NAS choice to make: go straight to iOS's confirmation.
                if !new.isEmpty, !needsChoice { perform(includingNAS: false) }
            }
            .alert("无法删除", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var title: String {
        hasLocal ? "这些项目在 NAS 上有备份。" : "NAS 上的原图将被永久删除，且无法恢复。"
    }

    private func perform(includingNAS: Bool) {
        let batch = targets
        targets = []
        Task {
            do {
                try await store.delete(batch, includingNAS: includingNAS)
                onDeleted()
            } catch let error as NSError where error.domain == "PHPhotosErrorDomain" && error.code == 3072 {
                // The user declined iOS's prompt; nothing changed and nothing needs saying.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
