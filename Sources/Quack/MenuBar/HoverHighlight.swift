import SwiftUI
import AppKit

/// AppKit-backed hover detection. SwiftUI's `.onHover`/`.onContinuousHover` are
/// laggy inside a `MenuBarExtra` window (the window isn't key, so mouse-moved
/// events are throttled). An `NSTrackingArea` with `.activeAlways` reports
/// enter/exit immediately regardless of key state.
private final class TrackingNSView: NSView {
    var onChange: (Bool) -> Void
    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }
    override func mouseEntered(with event: NSEvent) { onChange(true) }
    override func mouseExited(with event: NSEvent) { onChange(false) }
}

private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> NSView { TrackingNSView(onChange: onChange) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingNSView)?.onChange = onChange
    }
}

extension View {
    /// Reports hover state immediately (for menu-bar popover rows).
    func instantHover(_ hovering: Binding<Bool>) -> some View {
        background(HoverTracker { hovering.wrappedValue = $0 })
    }
}
