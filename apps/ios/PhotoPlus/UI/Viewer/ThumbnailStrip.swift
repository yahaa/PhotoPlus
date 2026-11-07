import SwiftUI

/// The strip above the toolbar. The current photo sits centred, apart from its neighbours,
/// and dragging the strip moves through the photos.
struct ThumbnailStrip: View {
    let items: [PhotoItem]
    @Binding var currentID: String?

    @State private var position = ScrollPosition(idType: String.self)
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(items) { thumbnail($0) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, geometry.size.width / 2)
            }
            .scrollPosition($position, anchor: .center)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                isDragging = phase == .interacting || phase == .decelerating
            }
            .onChange(of: position.viewID(type: String.self)) { _, id in
                if isDragging, let id, id != currentID { currentID = id }
            }
            .onChange(of: currentID) { _, id in
                if !isDragging { center(id, animated: true) }
            }
            .onChange(of: geometry.size.width, initial: true) { _, _ in
                // The first layout has no width yet, so centring has to wait for the next pass.
                DispatchQueue.main.async { center(currentID, animated: false) }
            }
        }
        .frame(height: 44)
        .accessibilityIdentifier("viewer-strip")
    }

    private func thumbnail(_ item: PhotoItem) -> some View {
        let isCurrent = item.id == currentID
        return ThumbnailView(item: item, pixelSize: 120)
            .frame(width: isCurrent ? 44 : 30, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(.horizontal, isCurrent ? 8 : 0)
            .contentShape(Rectangle())
            .onTapGesture { currentID = item.id }
            .id(item.id)
    }

    private func center(_ id: String?, animated: Bool) {
        guard let id else { return }
        var transaction = Transaction(animation: animated ? .snappy(duration: 0.2) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) { position.scrollTo(id: id, anchor: .center) }
    }
}
