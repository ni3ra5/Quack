import AppKit
import SwiftUI

/// A floating on-screen brightness overlay that mimics the native macOS
/// brightness HUD, shown on the external display being adjusted. Auto-hides
/// after a short delay.
@MainActor
final class BrightnessHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = BrightnessHUDModel()

    func show(displayName: String, level: Double, on screen: NSScreen?) {
        model.displayName = displayName
        model.level = max(0, min(1, level))

        let panel = ensurePanel()
        position(panel, on: screen)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleHide(panel)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: BrightnessHUDView(model: model))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)
        panel = p
        return p
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        // Top-right of the target screen, just inside the menu-bar area.
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = panel.frame.size
        let margin: CGFloat = 16
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - margin,
            y: frame.maxY - size.height - margin
        ))
    }

    private func scheduleHide(_ panel: NSPanel) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                panel.animator().alphaValue = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}

final class BrightnessHUDModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var level: Double = 0
}

private struct BrightnessHUDView: View {
    @ObservedObject var model: BrightnessHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 9) {
                Image(systemName: "sun.min.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                SegmentedBar(level: model.level)
                Image(systemName: "sun.max.fill").font(.system(size: 16)).foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 280, alignment: .leading)
        .background(HUDBackground())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A continuous brightness track with faint tick marks, like the native HUD.
private struct SegmentedBar: View {
    let level: Double
    private let ticks = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.22))
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white)
                    .frame(width: max(8, geo.size.width * CGFloat(min(max(level, 0), 1))))
                // Faint notch marks like the native HUD.
                HStack(spacing: 0) {
                    ForEach(0..<ticks, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Color.black.opacity(0.10)).frame(width: 1) }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, geo.size.width / CGFloat(ticks) / 2)
            }
        }
        .frame(height: 8)
    }
}

/// HUD-material blur background.
private struct HUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
