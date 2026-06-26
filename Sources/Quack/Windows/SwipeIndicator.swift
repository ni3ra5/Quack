import AppKit
import SwiftUI
import CoreGraphics
import QuackKit

/// A small arrow badge that sits **on** the cursor while a window-swipe is in
/// progress, effectively replacing the pointer with a directional arrow. A
/// yellow arrow on a dark circle. More reliable than `NSCursor` (which the
/// window server resets on every event during a passive scroll gesture); the
/// real cursor is hidden while the badge is shown.
@MainActor
final class SwipeIndicator {
    private var panel: NSPanel?
    private let model = SwipeIndicatorModel()
    private let size: CGFloat = 30

    /// Shows/updates the badge for `direction`, centered on `cursor`
    /// (Cocoa global, Y-up coords from `NSEvent.mouseLocation`).
    func show(direction: SwipeDirection, at cursor: CGPoint) {
        model.direction = direction
        let panel = ensurePanel()
        // The system arrow cursor draws down-and-right of its hotspot and always
        // sits above our window (the hardware cursor can't be reliably hidden
        // from a background app). Anchor the badge up-and-left of the hotspot so
        // the arrow stays fully visible right at the pointer.
        panel.setFrameOrigin(NSPoint(x: cursor.x - size + 6, y: cursor.y - 6))
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.08; panel.animator().alphaValue = 1 }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: SwipeIndicatorView(model: model))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)
        panel = p
        return p
    }
}

final class SwipeIndicatorModel: ObservableObject {
    @Published var direction: SwipeDirection = .right
}

private struct SwipeIndicatorView: View {
    @ObservedObject var model: SwipeIndicatorModel

    private var symbol: String {
        switch model.direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.8))
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 30, height: 30)
    }
}
