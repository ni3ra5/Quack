import AppKit
import SwiftUI
import QuackKit

/// One toast's content.
struct ToastItem: Identifiable {
    let id = UUID()
    let title: String
    let relativeText: String   // "in 10 min" / "now"
    let timeRange: String      // "4:22 – 5:07 PM"
    let colorHex: String?
    let joinURL: URL?
    let provider: MeetingProvider
    let joinable: Bool         // show the Join button (1-min + on-time reminders)
    let isStart: Bool          // a "join now" toast vs. an advance reminder
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
    private let width: CGFloat = 380
    private let gap: CGFloat = 10

    /// Shows a toast. When `dismissAfter` is nil the toast persists until the
    /// user joins or closes it (used for the "join now" toast).
    func show(_ item: ToastItem, dismissAfter seconds: TimeInterval?) {
        let panel = makePanel(for: item)
        let active = ActiveToast(item: item, panel: panel)
        toasts.insert(active, at: 0)
        reflow()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }

        if let seconds {
            let work = DispatchWorkItem { [weak self] in self?.dismiss(active) }
            active.dismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
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
        // Invert the theme relative to the OS: a white toast in dark mode, a dark
        // toast in light mode. Forcing the panel's appearance flips the material,
        // the window-background color, and SwiftUI's colorScheme together.
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        panel.appearance = NSAppearance(named: systemDark ? .aqua : .darkAqua)
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
        // Size to fit the content (including the outer margin that lets the
        // corner ✕ overhang without being clipped).
        let fitting = host.fittingSize
        panel.setContentSize(NSSize(width: max(width, fitting.width), height: max(60, fitting.height)))
        return panel
    }

    private func dismissPanel(_ panel: NSPanel) {
        if let active = toasts.first(where: { $0.panel === panel }) { dismiss(active) }
    }

    /// Re-positions all toasts stacked down from the top-right of the main screen.
    private func reflow() {
        // NSScreen.main can be nil/ambiguous for a background agent app with no
        // key window — fall back to the menu-bar screen so toasts never end up
        // positioned off-screen.
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.relativeText).foregroundStyle(Color.accentColor)
                    Text("·").foregroundStyle(.secondary)
                    Text(item.timeRange).foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .fixedSize()   // time line is always shown in full
            }
            Spacer(minLength: 14)
            if item.joinable, item.joinURL != nil {
                JoinButton(provider: item.provider, onJoin: onJoin)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        // Size to content (up to a cap) so the name and time aren't truncated.
        .frame(minWidth: 300, maxWidth: 480, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                }
                .buttonStyle(.plain)
                // Straddle the top-left corner like the native notification ✕.
                .offset(x: -8, y: -8)
            }
        }
        // Outer margin so the corner-straddling ✕ isn't clipped by the panel.
        .padding(8)
        .onContinuousHover { phase in
            switch phase {
            case .active: hovering = true
            case .ended: hovering = false
            }
        }
    }
}

/// A pill "Join <provider>" button that opens the meeting in the browser.
private struct JoinButton: View {
    let provider: MeetingProvider
    let onJoin: () -> Void

    var body: some View {
        Button(action: onJoin) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(provider.tint)
                Text(provider.joinLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

private extension MeetingProvider {
    /// Brand-ish tint for the join icon. (Exact provider logos would need bundled
    /// image assets; this approximates with the provider's brand color.)
    var tint: Color {
        switch self {
        case .googleMeet: return Color(red: 0.20, green: 0.66, blue: 0.33)   // Google green #34A853
        case .zoom: return Color(red: 0.18, green: 0.46, blue: 0.96)
        case .teams: return Color(red: 0.36, green: 0.36, blue: 0.84)
        case .webex: return Color(red: 0.0, green: 0.6, blue: 0.55)
        case .generic: return .accentColor
        }
    }
}

