import SwiftUI
import QuackKit

/// The reveal panel's content: when hovered, a black rounded strip showing the
/// mirrored crushed icons in a row; each tappable to forward the click. When not
/// hovered it collapses to a bare notch-width sliver that only detects hover.
struct NotchRevealView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in model.onHoverChange?(hovering) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen && !model.items.isEmpty {
            HStack(spacing: 10) {
                ForEach(model.items) { item in
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 18)
                        .onTapGesture { model.onTap?(item.source) }
                        .help("Reveal hidden menu bar item")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchShape().fill(Color.black))
        } else {
            // Collapsed: invisible hover target the width of the notch.
            Color.black.opacity(0.001)
        }
    }
}
