import SwiftUI
import UIKit

/// The grid's live scale while pinching. Its own object, so a pinch re-renders one modifier, not every cell.
@MainActor
final class GridPinch: ObservableObject {
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var anchor = UnitPoint.center

    func track(scale newScale: CGFloat, at point: UnitPoint, limit: CGFloat) {
        anchor = point
        scale = limit >= 1 ? min(newScale, limit * 1.1) : max(newScale, limit * 0.9)
    }

    func rebase(by ratio: CGFloat) {
        scale /= ratio
    }

    func settle() {
        withAnimation(.spring(duration: 0.3, bounce: 0)) { scale = 1 }
    }
}

struct PinchScaled<Content: View>: View {
    @ObservedObject var pinch: GridPinch
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().scaleEffect(pinch.scale, anchor: pinch.anchor)
    }
}

/// UIKit's recognizer, since SwiftUI's `MagnifyGesture` lost pinches to the scroll view.
struct GridPinchRecognizer: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat, UnitPoint) -> Void
    let onEnd: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            let size = recognizer.view?.bounds.size ?? CGSize(width: 1, height: 1)
            let point = recognizer.location(in: recognizer.view)
            onChange(recognizer.scale, UnitPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1)))
        case .ended, .cancelled, .failed:
            onEnd(recognizer.scale)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
