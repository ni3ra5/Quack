import AppKit
import SwiftUI
import QuackKit

/// One toast's content.
struct ToastItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let colorHex: String?
    let joinURL: URL?
    let isStart: Bool       // a "join now" toast vs. an advance reminder
}

/// Shows stacked, top-right toast notifications (Notion-Calendar style) as
/// borderless floating panels, independent of the system notification center.
@MainActor
final class ToastPresenter {
    private final class ActiveToast {
        let item: ToastItem
        let panel: NSPanel
        var dismiss: DispatchWorkItem?
        init(item: ToastItem, panel: NSPanel) { self.item = item; self.panel = panel }
    }

    private var toasts: [ActiveToast] = []
    private let width: CGFloat = 320
    private let gap: CGFloat = 10

    func show(_ item: ToastItem, dismissAfter seconds: TimeInterval) {
        let panel = makePanel(for: item)
        let active = ActiveToast(item: item, panel: panel)
        toasts.insert(active, at: 0)
        reflow()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }

        let work = DispatchWorkItem { [weak self] in self?.dismiss(active) }
        active.dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func dismiss(_ toast: ActiveToast) {
        toast.dismiss?.cancel()
        guard let idx = toasts.firstIndex(where: { $0 === toast }) else { return }
        toasts.remove(at: idx)
        NSAnimationContext.runAnimationGroup({
            $0.duration = 0.18
            toast.panel.animator().alphaValue = 0
        }, completionHandler: {
            toast.panel.orderOut(nil)
        })
        reflow()
    }

    private func makePanel(for item: ToastItem) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = ToastView(
            item: item,
            onJoin: { [weak self, weak panel] in
                if let url = item.joinURL { NSWorkspace.shared.open(url) }
                if let panel { self?.dismissPanel(panel) }
            },
            onClose: { [weak self, weak panel] in
                if let panel { self?.dismissPanel(panel) }
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(host)
        // Size to fit the content.
        let fitting = host.fittingSize
        panel.setContentSize(NSSize(width: width, height: max(72, fitting.height)))
        return panel
    }

    private func dismissPanel(_ panel: NSPanel) {
        if let active = toasts.first(where: { $0.panel === panel }) { dismiss(active) }
    }

    /// Re-positions all toasts stacked down from the top-right of the main screen.
    private func reflow() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        var y = screen.maxY - 16
        for toast in toasts {
            let size = toast.panel.frame.size
            let x = screen.maxX - size.width - 16
            toast.panel.setFrameOrigin(NSPoint(x: x, y: y - size.height))
            y -= size.height + gap
        }
    }
}

private struct ToastView: View {
    let item: ToastItem
    let onJoin: () -> Void
    let onClose: () -> Void
    @State private var hoveringClose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                Circle()
                    .fill(Color(hex: item.colorHex) ?? .accentColor)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hoveringClose ? 1 : 0.4)
                .onContinuousHover { phase in
                    switch phase { case .active: hoveringClose = true; case .ended: hoveringClose = false }
                }
            }
            if item.joinURL != nil {
                Button(action: onJoin) {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill")
                        Text(item.isStart ? "Join now" : "Join")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(item.isStart ? .green : .accentColor)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(ToastBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct ToastBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
