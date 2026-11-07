import SwiftUI

/// Liquid Glass on iOS 26, a material before it.
extension View {
    func glass<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }

    /// Darkens glass over darkened photos. Toolbar items ignore the color scheme for their glass.
    func darkGlass(_ isDark: Bool) -> some View {
        environment(\.usesDarkGlass, isDark)
    }

    @ViewBuilder func glassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Removes iOS 26's automatic blur where a screen draws its own fade.
    @ViewBuilder func hidesScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }

    /// Fades a screen's edge content under floating controls.
    func edgeFade(_ edge: VerticalEdge, color: Color, height: CGFloat) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            LinearGradient(colors: [color, color.opacity(0)], startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
                .frame(height: height)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

extension EnvironmentValues {
    @Entry var usesDarkGlass = false
}

private struct GlassBackground<S: Shape>: ViewModifier {
    @Environment(\.usesDarkGlass) private var isDark
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(isDark ? .regular.tint(.black.opacity(0.45)).interactive() : .regular.interactive(), in: shape)
        } else {
            content.background(isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial), in: shape)
        }
    }
}

/// Merges neighbouring glass shapes on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// A round glass icon, as used for the bars' standalone buttons.
struct GlassIcon: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glass(in: Circle())
    }
}
