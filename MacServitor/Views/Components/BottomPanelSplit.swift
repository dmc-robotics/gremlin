import AppKit
import SwiftUI

/// Main content above a panel whose height is set by dragging the divider.
/// Used instead of VSplitView, which lays out toolbar safe areas incorrectly.
struct BottomPanelSplit<Content: View, Panel: View>: View {
    @Binding var panelHeight: Double
    let minContentHeight: CGFloat
    let minPanelHeight: CGFloat
    @ViewBuilder let content: Content
    @ViewBuilder let panel: Panel

    @State private var dragStartHeight: Double?

    private static var handleHeight: CGFloat { 6 }

    var body: some View {
        GeometryReader { geometry in
            let maxPanelHeight = max(minPanelHeight, geometry.size.height - minContentHeight)
            let height = min(max(panelHeight, minPanelHeight), maxPanelHeight)

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                handle(maxPanelHeight: maxPanelHeight)
                panel
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }

    private func handle(maxPanelHeight: CGFloat) -> some View {
        Divider()
            .frame(height: Self.handleHeight)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: .top))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? panelHeight
                        dragStartHeight = start
                        panelHeight = min(max(start - value.translation.height, minPanelHeight), maxPanelHeight)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .accessibilityHidden(true)
    }
}
