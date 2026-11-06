import AppKit
import SwiftUI
import QuackKit

/// A black "chin" under the MacBook notch with one dot per Claude session.
/// Clicking expands it into a list where sessions can be removed; moving the
/// mouse away closes it. On screens without a notch it draws a small fake
/// notch at the top-centre instead.
///
/// Mouse-exit uses a plain NSTrackingArea on our own panel: no event taps, no
/// Accessibility permission.
@MainActor
final class NotchPanelController {
    final class Model: ObservableObject {
        @Published var sessions: [ClaudeSession] = []
        /// The app each session runs in (Claude, VS Code, cmux…), by pid.
        @Published var apps: [Int32: NSRunningApplication] = [:]
        @Published var expanded = false
        @Published var notchHeight: CGFloat = 32
        @Published var collapsedSize = CGSize(width: 200, height: 46)
        @Published var expandedSize = CGSize(width: 360, height: 200)
    }

    /// One animation for the black shape growing and the dots flying into
    /// their rows, so they move together.
    private static let morph = Animation.spring(response: 0.2, dampingFraction: 0.9)

    private let model = Model()
    private let onOpen: (ClaudeSession) -> Void
    private let onDismiss: (String) -> Void
    private var panel: NSPanel?
    /// The window is resized instantly (it is transparent); SwiftUI animates
    /// the visible shape inside it. While collapsing, the window stays big
    /// until the shrink animation has finished.
    private var windowExpanded = false
    private var collapseWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    private let chinHeight: CGFloat = 14
    private let rowHeight: CGFloat = 46
    private let headerHeight: CGFloat = 30   // 24 + 6 bottom padding
    private let projectHeaderHeight: CGFloat = 20
    private let expandedWidth: CGFloat = 360

    init(onOpen: @escaping (ClaudeSession) -> Void, onDismiss: @escaping (String) -> Void) {
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }
    }

    func update(sessions: [ClaudeSession], apps: [Int32: NSRunningApplication] = [:]) {
        guard sessions != model.sessions || apps != model.apps
                || (sessions.isEmpty && panel?.isVisible == true) else { return }
        model.sessions = sessions
        model.apps = apps
        if sessions.isEmpty {
            model.expanded = false
            windowExpanded = false
            panel?.orderOut(nil)
            return
        }
        let p = panel ?? makePanel()
        layout()
        if !p.isVisible { p.orderFrontRegardless() }
    }

    // MARK: Geometry

    /// The notched built-in screen if there is one, else the menu-bar screen.
    private func targetScreen() -> (screen: NSScreen, notchWidth: CGFloat, notchHeight: CGFloat)? {
        for s in NSScreen.screens where s.safeAreaInsets.top > 0 {
            if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
                return (s, r.minX - l.maxX, s.safeAreaInsets.top)
            }
        }
        guard let s = NSScreen.screens.first else { return nil }
        return (s, 0, s.frame.maxY - s.visibleFrame.maxY)   // menu-bar height
    }

    private func layout() {
        guard let panel, let target = targetScreen() else { return }
        model.notchHeight = target.notchHeight
        let groups = CGFloat(model.groups.count)
        let dotsWidth = CGFloat(model.sessions.count) * 11 + 26
        let collapsed = CGSize(width: max(target.notchWidth, dotsWidth), height: target.notchHeight + chinHeight)
        let expanded = CGSize(width: max(expandedWidth, target.notchWidth + 40),
                              height: target.notchHeight + groups * headerHeight
                                + CGFloat(model.groups.reduce(0) { $0 + $1.projects.count }) * projectHeaderHeight
                                + CGFloat(model.groups.reduce(0) { $0 + $1.projects.count - 1 }) * 9   // project dividers
                                + (groups - 1) * 9   // app dividers
                                + CGFloat(model.sessions.count) * rowHeight + 12)
        if model.collapsedSize != collapsed { model.collapsedSize = collapsed }
        if model.expandedSize != expanded { model.expandedSize = expanded }

        let size = windowExpanded ? expanded : collapsed
        let f = target.screen.frame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func expand() {
        collapseWork?.cancel()
        guard !model.expanded else { return }
        windowExpanded = true
        layout()
        withAnimation(Self.morph) { model.expanded = true }
    }

    private func collapse() {
        collapseWork?.cancel()
        guard model.expanded else { return }
        withAnimation(Self.morph) { model.expanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.model.expanded else { return }
            self.windowExpanded = false
            self.layout()
        }
    }

    // MARK: Hover

    /// Opens on click (see NotchView); hovering only keeps it open, and
    /// leaving closes it.
    private func hoverChanged(_ inside: Bool) {
        collapseWork?.cancel()
        if !inside {
            // Small grace period so brushing past the edge doesn't flicker.
            let work = DispatchWorkItem { [weak self] in self?.collapse() }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Above the menu bar so it can sit over the notch area.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false

        let hover = HoverView()
        hover.onHover = { [weak self] in self?.hoverChanged($0) }
        let host = NSHostingView(rootView: NotchView(
            model: model,
            onExpand: { [weak self] in self?.expand() },
            onOpen: { [weak self] session in
                guard let self else { return }
                self.collapse()
                self.onOpen(session)
            },
            onDismiss: { [weak self] in self?.onDismiss($0) }))
        host.autoresizingMask = [.width, .height]
        hover.addSubview(host)
        p.contentView = hover
        host.frame = hover.bounds
        panel = p
        return p
    }
}

/// Reports mouse enter/exit even though our panel never becomes key.
private final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

// MARK: - SwiftUI

/// Sessions running in one app, e.g. all Claude-app sessions or all cmux ones.
struct AppGroup: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let sessions: [ClaudeSession]

    /// Sessions split by project folder, in order of first appearance.
    var projects: [(cwd: String, name: String, sessions: [ClaudeSession])] {
        var order: [String] = []
        var byCwd: [String: [ClaudeSession]] = [:]
        for s in sessions {
            if byCwd[s.cwd] == nil { order.append(s.cwd) }
            byCwd[s.cwd, default: []].append(s)
        }
        return order.map { ($0, ($0 as NSString).lastPathComponent, byCwd[$0]!) }
    }
}

extension NotchPanelController.Model {
    /// Grouped by the actual app (so cmux and Terminal are separate), ordered
    /// Claude → VS Code-likes → terminals, then by app name.
    var groups: [AppGroup] {
        sessions.groupedBySource.flatMap { source, list in
            Dictionary(grouping: list) { apps[$0.pid]?.bundleIdentifier ?? source.rawValue }
                .map { key, members in
                    let app = apps[members[0].pid]
                    return AppGroup(id: key, name: app?.localizedName ?? source.label,
                                    icon: app?.icon, sessions: members)
                }
                .sorted { $0.name < $1.name }
        }
    }
}

private struct NotchView: View {
    @ObservedObject var model: NotchPanelController.Model
    let onExpand: () -> Void
    let onOpen: (ClaudeSession) -> Void
    let onDismiss: (String) -> Void
    @Namespace private var dots

    var body: some View {
        let size = model.expanded ? model.expandedSize : model.collapsedSize
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notchHeight)   // behind the physical notch
            if model.expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.groups) { group in
                        if group.id != model.groups.first?.id {
                            Divider().overlay(Color.white.opacity(0.2)).padding(.top, 8)   // between apps
                        }
                        HStack(spacing: 6) {
                            if let icon = group.icon {
                                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            }
                            Text(group.name.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 24, alignment: .bottomLeading)
                        .padding(.leading, 4)
                        .padding(.bottom, 6)   // breathing room above the first row
                        ForEach(group.projects, id: \.cwd) { project in
                            if project.cwd != group.projects.first?.cwd {
                                Divider().overlay(Color.white.opacity(0.05)).padding(.vertical, 4)   // between projects
                            }
                            HStack(spacing: 5) {
                                Image(systemName: "folder").font(.system(size: 10))
                                Text(project.name).font(.system(size: 11))
                            }
                            .foregroundStyle(.secondary)
                            .frame(height: 20, alignment: .leading)
                            .padding(.leading, 12)   // tree: app › project › session
                            ForEach(project.sessions) {
                                SessionRow(session: $0, dots: dots, onOpen: onOpen, onDismiss: onDismiss)
                                    .padding(.leading, 20)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .transition(.opacity)
            } else {
                HStack(spacing: 5) {   // same order as the list, no gap between apps
                    ForEach(model.groups.flatMap(\.sessions)) {
                        StateDot(state: $0.state, size: 6)
                            .matchedGeometryEffect(id: $0.id, in: dots)
                    }
                }
                .frame(height: 10)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        // Collapsed: just the dots. Near-zero (not zero) alpha keeps the area
        // hit-testable so hovering the notch still opens the list.
        .background(NotchShape(radius: model.expanded ? 16 : 8)
            .fill(Color.black.opacity(model.expanded ? 1 : 0.001)))
        .clipShape(NotchShape(radius: model.expanded ? 16 : 8))
        // Click the notch/dots to open. Rows and ✕ handle their own clicks.
        .contentShape(NotchShape(radius: 8))
        .onTapGesture { if !model.expanded { onExpand() } }
        // Pinned to the top-centre of the (possibly larger) window.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let dots: Namespace.ID
    let onOpen: (ClaudeSession) -> Void
    let onDismiss: (String) -> Void
    @State private var hovering = false
    @State private var rowHovering = false

    var body: some View {
        HStack(spacing: 10) {
            StateDot(state: session.state, size: 8)
                .matchedGeometryEffect(id: session.id, in: dots)   // flies in from the notch
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.system(size: 13)).lineLimit(1)
                Text(stateText).fontWeight(.medium).foregroundColor(session.state.color)
                    .font(.system(size: 11)).lineLimit(1)   // project is in the header above
            }
            Spacer(minLength: 0)
            Button { onDismiss(session.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(hovering ? 0.18 : 0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Remove from the list (the session keeps running)")
            .onHover { hovering = $0 }
        }
        .frame(height: 46)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(rowHovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(session) }   // the ✕ button takes its own clicks
        .onHover { rowHovering = $0 }
        .foregroundStyle(.white)
    }

    private var stateText: String {
        switch session.state {
        case .waiting: return "Needs you"
        case .done: return "Done"
        case .running: return "Working"
        case .idle: return "Idle"
        }
    }
}

private struct StateDot: View {
    let state: ClaudeSessionState
    let size: CGFloat

    var body: some View {
        // Opacity computed from the clock, not a SwiftUI repeatForever
        // animation: those can't be reliably started/stopped when the state
        // changes under an existing view (blue stopped blinking, yellow kept it).
        // ponytail: redraws a 6pt dot at 30 fps while a session works; fine.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !blinks)) { ctx in
            Circle()
                .fill(state.color)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 1)   // readable on light windows too
                .opacity(blinks ? opacity(at: ctx.date) : 1)
        }
    }

    private var blinks: Bool { state == .running }

    /// Smooth 0.7 s fade between 1 and 0.25.
    private func opacity(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate * 2 * .pi / 0.7
        return 0.625 + 0.375 * cos(phase)
    }
}

private extension ClaudeSessionState {
    var color: Color {
        switch self {
        case .waiting: return .red
        case .done: return .yellow
        case .running: return .blue
        case .idle: return Color(white: 0.45)
        }
    }
}

/// A rectangle with only the bottom corners rounded (macOS 13 has no
/// UnevenRoundedRectangle).
private struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
