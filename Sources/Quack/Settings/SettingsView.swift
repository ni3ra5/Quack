import SwiftUI
import QuackKit

/// The feature groups shown in the left sidebar. `general` is the schedule
/// (agenda) view; `settings` holds the app-level preferences.
enum SettingsTab: String, CaseIterable {
    case general, calendar, temperature, display, windows, permissions, settings

    var title: String {
        switch self {
        case .general: return "Dashboard"
        case .calendar: return "Calendar"
        case .display: return "Display"
        case .temperature: return "CPU"
        case .windows: return "Windows"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .display: return "sun.max"
        case .temperature: return "thermometer.medium"
        case .windows: return "macwindow.on.rectangle"
        case .permissions: return "lock.shield"
        case .settings: return "gearshape"
        }
    }
}

/// Named groupings for the sidebar (CleanMyMac-style section headers). `General`
/// sits alone at the top; `Settings` sits alone at the bottom.
private enum SidebarGroup: String, CaseIterable {
    case top = ""
    case menuBar = "Menu Bar"
    case controls = "Controls"
    case system = "System"
    case bottom = " "

    var tabs: [SettingsTab] {
        switch self {
        case .top: return [.general]
        case .menuBar: return [.calendar, .temperature]
        case .controls: return [.display, .windows]
        case .system: return [.permissions]
        case .bottom: return [.settings]
        }
    }

    /// Whether to render a visible header label (top/bottom are unlabeled).
    var showsHeader: Bool { self != .top && self != .bottom }
}

/// The whole settings window: an immersive full-height sidebar (grouped nav,
/// traffic-light-aware app title) on the left and the selected pane on the
/// right. Uses `NavigationSplitView` so the sidebar material, selection
/// highlight, and light/dark colors are all native and adapt to the appearance.
struct SettingsRootView: View {
    @EnvironmentObject var env: AppEnvironment

    private var selection: Binding<SettingsTab?> {
        Binding(get: { env.settingsTab }, set: { if let new = $0 { env.settingsTab = new } })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 280)
        } detail: {
            SettingsPane(tab: env.settingsTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, idealWidth: 820, minHeight: 560, idealHeight: 660)
        .font(.system(size: 14))
        .tint(.accentColor)
        .onAppear { env.permissions.refreshAll() }
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SidebarGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(group.tabs, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                } header: {
                    if group.showsHeader { Text(group.rawValue) }
                }
            }
        }
        .listStyle(.sidebar)
        // Immersive: the sidebar material runs full-height under the transparent
        // title bar; this inset keeps the static app name beside the traffic
        // lights without pushing the list content under them.
        .safeAreaInset(edge: .top, spacing: 0) { appIdentity }
        // Quit is always reachable, pinned to the very bottom of the sidebar.
        .safeAreaInset(edge: .bottom, spacing: 0) { quitFooter }
    }

    private var quitFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "power").font(.system(size: 13, weight: .semibold)).frame(width: 20)
                    Text("Quit Quack").font(.system(size: 14))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 4)
    }

    private var appIdentity: some View {
        HStack(spacing: 7) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 18, height: 18)
            Text("Quack").font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.leading, 78)   // clear the traffic-light cluster
        .padding(.trailing, 12)
        .frame(height: 28)       // align with the title-bar height
        .padding(.top, 6).padding(.bottom, 8)
    }
}

/// One settings pane. The `general` tab is the custom schedule view; every
/// other tab is a grouped `Form`.
struct SettingsPane: View {
    let tab: SettingsTab
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Group {
            switch tab {
            case .general:
                DashboardView()
            default:
                Form {
                    switch tab {
                    case .calendar:
                        CalendarSection()
                        RemindersSection()
                    case .display:
                        BrightnessSection()
                    case .temperature:
                        TemperatureSection()
                    case .windows:
                        WindowSwipeSection()
                        DockGesturesSection()
                        KeyboardShortcutsSection()
                        NotchRevealSection()
                    case .permissions:
                        PermissionsSection()
                        StatusSection()
                    case .settings:
                        SettingsSection()
                    case .general:
                        EmptyView()  // shouldn't reach here
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)   // let the darker window bg show through
            }
        }
    }
}

/// A subtle inline caption about how cross-app calendar edits sync. Plain
/// secondary text (no tint, no border) so it sits quietly inside its card and
/// scrolls with the content.
private struct CalendarSyncTip: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
            Text("Edits made in another app (Google, Notion, etc.) appear after macOS syncs them. If they're slow, shorten **Calendar app → Settings → Accounts → Refresh Calendars**.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Settings (app-level preferences)

private struct SettingsSection: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
      Group {
        let s = env.settingsStore
        Section("General") {
            Toggle("Launch Quack at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.set($0) }
            Toggle("Hide the duck icon from the menu bar", isOn: s.binding(\.hideDuckIcon))
            Text("The dropdown and settings are still reachable from the meeting countdown and temperature items.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Section("Appearance") {
            Picker("Theme", selection: appearanceBinding) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("System follows your macOS Light/Dark setting and switches with it.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
      }
      .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    /// Bridges the string-backed `appearance` setting to the `AppAppearance`
    /// enum the picker uses. Persisting the change triggers the app-wide
    /// re-apply wired up in `AppEnvironment`.
    private var appearanceBinding: Binding<AppAppearance> {
        let s = env.settingsStore
        return Binding(
            get: { AppAppearance.from(s.settings.appearance) },
            set: { mode in s.update { $0.appearance = mode.rawValue } }
        )
    }
}

// MARK: - Dashboard (General tab)

/// The Dashboard tab: a full-width Calendar card listing the next few events,
/// then a grid of summary cards for the other feature areas. Each card opens
/// its tab on click.
private struct DashboardView: View {
    @EnvironmentObject var env: AppEnvironment
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    @State private var upcoming: [MeetingEvent] = []
    @State private var tempC: Double = -1

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashCard(tab: .calendar) { calendarCardContent }
                LazyVGrid(columns: columns, spacing: 14) {
                    DashCard(tab: .temperature) { cpuSummary }
                    DashCard(tab: .display) { displaySummary }
                    DashCard(tab: .windows) { windowsSummary }
                    DashCard(tab: .permissions) { permissionsSummary }
                }
            }
            .padding(20)
        }
        .background(.background)
        .onAppear { env.refreshCalendarNow() }
        .task { await loadUpcoming() }
        .task { await pollTemperature() }
    }

    // MARK: Calendar (expanded — next 5 events inline)

    @ViewBuilder private var calendarCardContent: some View {
        if env.permissions.status(for: .calendar) != .granted {
            gist("Access needed", "Grant Calendar access", tint: .orange)
        } else if upcoming.isEmpty {
            gist("No upcoming meetings", "Nothing in the next two weeks")
        } else {
            VStack(spacing: 7) {
                ForEach(upcoming) { miniRow($0) }
            }
            .padding(.top, 2)
        }
    }

    private func miniRow(_ e: MeetingEvent) -> some View {
        HStack(spacing: 9) {
            Circle().fill(Color(hex: e.calendarColorHex) ?? .accentColor).frame(width: 7, height: 7)
            Text(whenText(e))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(e.title).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 4)
            if e.conferencingURL != nil {
                Image(systemName: "video.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .opacity(e.end <= env.now && !e.isInProgress(at: env.now) ? 0.5 : 1)
    }

    /// "2:30 PM" for today, "Fri 2:30 PM" otherwise; "All day" variants too.
    private func whenText(_ e: MeetingEvent) -> String {
        let today = Calendar.current.isDateInToday(e.start)
        if e.isAllDay { return today ? "All day" : "\(Self.wday.string(from: e.start)) · All day" }
        let t = Self.time.string(from: e.start)
        return today ? t : "\(Self.wday.string(from: e.start)) \(t)"
    }

    private func loadUpcoming() async {
        guard env.permissions.status(for: .calendar) == .granted else { return }
        let now = env.now
        let window = DateInterval(start: now, duration: 14 * 86_400)
        let all = await env.events(in: window)
        upcoming = Array(all.filter { $0.isAllDay || $0.end > now }.prefix(5))
    }

    private func pollTemperature() async {
        while !Task.isCancelled {
            tempC = await env.currentCPUTemperatureC()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }

    // MARK: CPU (live temperature)

    @ViewBuilder private var cpuSummary: some View {
        let s = env.settingsStore.settings
        let f = s.temperatureFahrenheit
        if tempC > 0 {
            let v = f ? tempC * 9 / 5 + 32 : tempC
            gist("\(Int(v.rounded()))°\(f ? "F" : "C")",
                 s.cpuTemperatureEnabled ? "Showing in menu bar" : "Not in menu bar",
                 tint: tempTint(tempC))
        } else {
            gist("Reading…", "Unit: \(f ? "Fahrenheit" : "Celsius")")
        }
    }

    /// Green / orange / red by CPU temperature (°C), matching the menu-bar item.
    private func tempTint(_ c: Double) -> Color {
        if c >= 85 { return .red }
        if c >= 70 { return .orange }
        return .green
    }

    @ViewBuilder private var displaySummary: some View {
        let s = env.settingsStore.settings
        if s.brightnessEnabled {
            let n = env.diagnostics.externalDisplayCount
            gist("F1 / F2 routing on", "\(n) external display\(n == 1 ? "" : "s")", tint: .green)
        } else {
            gist("Off", "Control external brightness with F1 / F2")
        }
    }

    private var windowsSummary: some View {
        let s = env.settingsStore.settings
        var on: [String] = []
        if s.windowShortcutsEnabled { on.append("Shortcuts") }
        if s.windowSwipeEnabled { on.append("Swipe") }
        if s.dockPinchQuitEnabled || s.windowPinchCloseEnabled { on.append("Pinch") }
        return Group {
            if on.isEmpty {
                gist("All off", "Shortcuts, swipe & pinch gestures")
            } else {
                gist(on.joined(separator: " · ") + " on", "Window management", tint: .green)
            }
        }
    }

    @ViewBuilder private var permissionsSummary: some View {
        let kinds = PermissionKind.allCases
        let granted = kinds.filter { env.permissions.status(for: $0) == .granted }.count
        let denied = kinds.contains { env.permissions.status(for: $0) == .denied }
        let all = granted == kinds.count
        gist("\(granted) of \(kinds.count) granted",
             denied ? "Some access denied" : (all ? "All set" : "Tap to manage"),
             tint: all ? .green : .orange)
    }

    private func gist(_ primary: String, _ secondary: String?, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(primary).font(.system(size: 13, weight: .medium)).foregroundStyle(tint).lineLimit(1)
            if let secondary {
                Text(secondary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    private static let wday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
}

/// A single dashboard card: feature icon + title + chevron over a gist. Opens
/// the matching tab when clicked.
private struct DashCard<Content: View>: View {
    @EnvironmentObject var env: AppEnvironment
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { env.settingsTab = tab } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor).frame(width: 20)
                    Text(tab.title).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                }
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .instantHover($hovering)
    }
}

// MARK: - Calendar agenda (Calendar tab)

/// A month-at-a-time agenda (Google "Schedule" style): a scrolling list grouped
/// by day, each day a date column beside its events. Pages by month and jumps
/// back to today. Reads events via `AppEnvironment.events(in:)`.
private struct CalendarAgendaView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var events: [MeetingEvent] = []
    @State private var loading = false

    private let cal = Calendar.current

    private var monthInterval: DateInterval {
        cal.dateInterval(of: .month, for: anchor) ?? DateInterval(start: anchor, duration: 30 * 86_400)
    }

    private var isCurrentMonth: Bool {
        cal.isDate(anchor, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .task(id: anchor) { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button("Today") { withAnimation { anchor = cal.startOfDay(for: Date()) } }
                .controlSize(.large)
                .disabled(isCurrentMonth)
            HStack(spacing: 2) {
                stepMonth("chevron.left", by: -1)
                stepMonth("chevron.right", by: 1)
            }
            Text(Self.month.string(from: anchor))
                .font(.system(size: 19, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func stepMonth(_ icon: String, by months: Int) -> some View {
        Button {
            if let next = cal.date(byAdding: .month, value: months, to: anchor) {
                withAnimation(.easeOut(duration: 0.15)) { anchor = next }
            }
        } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 26)
        }
        .buttonStyle(.borderless)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if env.permissions.status(for: .calendar) != .granted {
            emptyState(icon: "calendar.badge.exclamationmark",
                       title: "Calendar access needed",
                       subtitle: "Grant Calendar access to see your schedule.",
                       action: ("Grant", { env.requestCalendarAccess() }))
        } else if loading && events.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 44)
        } else if sections.isEmpty {
            emptyState(icon: "calendar",
                       title: "No events",
                       subtitle: "Nothing scheduled this month.",
                       action: nil)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(sections) { section in
                    dayRow(section)
                    Divider().padding(.leading, 84)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dayRow(_ section: DaySection) -> some View {
        HStack(alignment: .top, spacing: 8) {
            dayColumn(section.dayStart)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(section.events) { AgendaEventRow(event: $0, now: env.now) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 20)
    }

    private func dayColumn(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(isToday ? AnyView(Circle().fill(Color.accentColor)) : AnyView(Color.clear))
            Text(Self.dayLabel.string(from: day).uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
        }
        .frame(width: 56)
        .padding(.top, 8)
    }

    private func emptyState(icon: String, title: String, subtitle: String,
                            action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action { Button(action.0) { action.1() }.padding(.top, 4) }
        }
        .frame(maxWidth: .infinity).padding(.top, 52).padding(.horizontal, 24)
    }

    /// Events grouped into day buckets (all events in the month, including past
    /// ones, so navigating back shows history). All-day events sort first.
    private var sections: [DaySection] {
        let grouped = Dictionary(grouping: events) { cal.startOfDay(for: $0.start) }
        return grouped
            .map { day, evs in
                DaySection(dayStart: day, events: evs.sorted { a, b in
                    a.isAllDay != b.isAllDay ? a.isAllDay : a.start < b.start
                })
            }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private func load() async {
        loading = true
        events = await env.events(in: monthInterval)
        loading = false
    }

    private static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f
    }()
    private static let dayLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM, EEE"; return f
    }()
}

/// One agenda line: calendar-color dot, time range, title, location, join icon.
private struct AgendaEventRow: View {
    let event: MeetingEvent
    let now: Date
    @State private var hovering = false

    private var isPast: Bool { event.end <= now && !event.isInProgress(at: now) }

    var body: some View {
        Button { if let u = event.conferencingURL { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: event.calendarColorHex) ?? .accentColor)
                    .frame(width: 10, height: 10)
                Text(timeText)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(width: 108, alignment: .leading)
                Text(event.title).font(.system(size: 14)).lineLimit(1)
                if let loc = event.location, !loc.isEmpty {
                    Text(loc).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if event.conferencingURL != nil {
                    Image(systemName: "video.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
            .opacity(isPast ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .instantHover($hovering)
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        return "\(Self.time.string(from: event.start)) – \(Self.time.string(from: event.end))"
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
}

// MARK: - Calendar

private struct CalendarSection: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var accounts: [CalendarAccountInfo] = []

    var body: some View {
      Group {
        let s = env.settingsStore

        Section {
            Toggle("Show meeting countdown in the menu bar", isOn: s.binding(\.menuBarCountdownEnabled))
            if env.permissions.status(for: .calendar) == .granted {
                CalendarSyncTip()
            }
        }

            if env.permissions.status(for: .calendar) != .granted {
                Section {
                    HStack {
                        Text("Calendar access is needed to read your events.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Spacer()
                        Button("Grant") { env.requestCalendarAccess() }
                    }
                }
            } else {
                // One card per account; children are dividers within the card.
                // The first card carries the group header.
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    Section {
                        Toggle(isOn: accountBinding(account)) {
                            Text(account.title).fontWeight(.semibold)
                        }
                        // Children only show while the account is on.
                        if isAccountOn(account) {
                            ForEach(account.calendars) { cal in
                                // A provider's primary calendar is named after the
                                // account itself — relabel it so it isn't a confusing
                                // repeat of the account row above.
                                Toggle(calendarLabel(cal, in: account), isOn: calendarBinding(cal.id))
                                    .padding(.leading, 14)
                            }
                        }
                    } header: {
                        if index == 0 { Text("Calendar accounts") }
                    }
                }

                if accounts.isEmpty {
                    Section { Text("No calendars found.").font(.system(size: 12)).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Add or remove accounts…") { env.openInternetAccounts() }
                    Button("Refresh calendars") { accounts = env.availableAccounts() }
                    Text("Accounts are added in System Settings → Internet Accounts.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
      }
      .onAppear { accounts = env.availableAccounts() }
    }

    /// Display name for a calendar row. The provider's primary calendar shares
    /// the account's name (e.g. the email), so show "Primary calendar" instead
    /// of repeating it under the account toggle.
    private func calendarLabel(_ cal: CalendarInfo, in account: CalendarAccountInfo) -> String {
        cal.title == account.title ? "Primary calendar" : cal.title
    }

    private var allCalendarIDs: [String] {
        accounts.flatMap { $0.calendars.map(\.id) }
    }

    /// True when calendar `id` is currently synced. With `syncAllCalendars` on,
    /// every calendar reads as on.
    private func isOn(_ id: String) -> Bool {
        let s = env.settingsStore.settings
        return s.syncAllCalendars || s.selectedCalendarIDs.contains(id)
    }

    /// An account is "on" while ANY of its calendars is synced — so turning one
    /// child off does not collapse the account. Off only when all are off.
    private func isAccountOn(_ account: CalendarAccountInfo) -> Bool {
        account.calendars.contains { isOn($0.id) }
    }

    private func accountBinding(_ account: CalendarAccountInfo) -> Binding<Bool> {
        let ids = account.calendars.map(\.id)
        return Binding(
            get: { isAccountOn(account) },
            set: { on in
                var sel = currentSelection
                if on { sel.formUnion(ids) } else { sel.subtract(ids) }
                setSelection(sel)
            }
        )
    }

    /// Applies a new explicit selection, collapsing back to "sync all" when the
    /// selection covers every known calendar (keeps the stored set tidy).
    private func setSelection(_ ids: Set<String>) {
        let all = Set(allCalendarIDs)
        env.settingsStore.update {
            if !all.isEmpty && all.isSubset(of: ids) {
                $0.syncAllCalendars = true
                $0.selectedCalendarIDs = []
            } else {
                $0.syncAllCalendars = false
                $0.selectedCalendarIDs = Array(ids)
            }
        }
    }

    /// The current effective selection as a concrete set (materializing the
    /// "sync all" state into the full list of ids).
    private var currentSelection: Set<String> {
        let s = env.settingsStore.settings
        return s.syncAllCalendars ? Set(allCalendarIDs) : Set(s.selectedCalendarIDs)
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { isOn(id) },
            set: { on in
                var sel = currentSelection
                if on { sel.insert(id) } else { sel.remove(id) }
                setSelection(sel)
            }
        )
    }
}

// MARK: - Keyboard shortcuts

private struct KeyboardShortcutsSection: View {
    @EnvironmentObject var env: AppEnvironment

    // Bit values matching QuackSettings.windowShortcutModifiers.
    private let modifiers: [(name: String, symbol: String, bit: Int)] = [
        ("Control", "⌃", 0b0100), ("Option", "⌥", 0b0010),
        ("Shift", "⇧", 0b1000), ("Command", "⌘", 0b0001),
    ]

    var body: some View {
        let s = env.settingsStore
        Section("Keyboard shortcuts") {
            Toggle("Window management shortcuts", isOn: s.binding(\.windowShortcutsEnabled))
            if s.settings.windowShortcutsEnabled {
                LabeledContent("Modifier") {
                    HStack(spacing: 6) {
                        ForEach(modifiers, id: \.bit) { mod in
                            Toggle(mod.symbol, isOn: bitBinding(mod.bit))
                                .toggleStyle(.button)
                        }
                    }
                }
                if modifierString.isEmpty {
                    Text("Pick at least one modifier.").font(.system(size: 12)).foregroundStyle(.orange)
                } else {
                    Text("\(modifierString) + arrows:  ↑ maximize (press again → monitor above) · ↓ move to the monitor below · ← left half (again → monitor left) · → right half (again → monitor right).")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Requires Accessibility permission.").font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                }
            }
        }
    }

    private var modifierString: String {
        let m = env.settingsStore.settings.windowShortcutModifiers
        return modifiers.filter { m & $0.bit != 0 }.map(\.symbol).joined()
    }

    private func bitBinding(_ bit: Int) -> Binding<Bool> {
        let s = env.settingsStore
        return Binding(
            get: { s.settings.windowShortcutModifiers & bit != 0 },
            set: { on in
                s.update {
                    if on { $0.windowShortcutModifiers |= bit } else { $0.windowShortcutModifiers &= ~bit }
                }
            }
        )
    }
}

// MARK: - Reminders

private struct RemindersSection: View {
    @EnvironmentObject var env: AppEnvironment
    var body: some View {
        let s = env.settingsStore
        Group {
            Section("Reminders") {
                Toggle("Meeting reminders", isOn: s.binding(\.remindersEnabled))
                if s.settings.remindersEnabled {
                    if !s.settings.calendarEnabled {
                        Text("Requires Calendar to be enabled.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    // Advance notifications (no Join button).
                    ForEach([20, 10, 5], id: \.self) { lead in
                        Toggle("\(lead) minutes before", isOn: leadBinding(lead))
                            .padding(.leading, 14)
                    }
                    Button("Preview notification") { env.previewReminderToast() }
                        .padding(.leading, 14)

                    // Join-now alerts (with the Join button).
                    Toggle("1 minute before", isOn: leadBinding(1))
                        .padding(.leading, 14)
                    Toggle("On time", isOn: s.binding(\.remindAtStart))
                        .padding(.leading, 14)
                    Button("Preview join alert") { env.previewToast() }
                        .padding(.leading, 14)
                }
            }

            if s.settings.remindersEnabled {
                Section("Sound") {
                    soundPicker("Notification sound", binding: s.binding(\.notificationSound))
                    soundPicker("Join alert sound", binding: s.binding(\.joinAlertSound))
                }
            }
        }
    }

    /// A sound picker that previews the sound as soon as one is chosen.
    @ViewBuilder
    private func soundPicker(_ label: String, binding: Binding<String>) -> some View {
        Picker(label, selection: binding) {
            ForEach(NotificationSound.allCases) { sound in
                Text(sound.displayName).tag(sound.rawValue)
            }
        }
        .onChange(of: binding.wrappedValue) { env.previewSound(NotificationSound.from($0)) }
    }

    private func leadBinding(_ lead: Int) -> Binding<Bool> {
        let s = env.settingsStore
        return Binding(
            get: { s.settings.reminderLeadMinutes.contains(lead) },
            set: { isOn in
                s.update {
                    var leads = Set($0.reminderLeadMinutes)
                    if isOn { leads.insert(lead) } else { leads.remove(lead) }
                    $0.reminderLeadMinutes = leads.sorted(by: >)
                }
            }
        )
    }
}

// MARK: - Brightness

private struct BrightnessSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("External-display brightness") {
            Toggle("Control external brightness with F1 / F2 keys", isOn: s.binding(\.brightnessEnabled))
            Text("When the cursor is on an external display, the brightness keys adjust that monitor over DDC instead of the built-in screen.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            if !env.brightnessController.isSupportedPlatform {
                Text("Brightness control is unavailable on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else if s.settings.brightnessEnabled {
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("F1 / F2 routing needs Accessibility permission (the slider still works without it).")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                }
                Stepper("Step: \(s.settings.brightnessStepPercent)%",
                        value: s.binding(\.brightnessStepPercent), in: 1...50, step: 1)
                Toggle("Dim the inactive display", isOn: s.binding(\.dimInactiveDisplay))
                if env.brightnessController.displays.isEmpty {
                    Text("No external displays detected.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(env.brightnessController.displays) { display in
                    DisplayRow(display: display)
                }
                Button("Re-scan displays") { env.brightnessController.refreshDisplays() }
            }
        }
    }
}

private struct DisplayRow: View {
    @EnvironmentObject var env: AppEnvironment
    let display: ControllableDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(display.name)
                Spacer()
                Text(display.supportsDDC ? "DDC supported" : "DDC not supported")
                    .font(.system(size: 12))
                    .foregroundStyle(display.supportsDDC ? .green : .secondary)
            }
            if display.supportsDDC {
                Slider(value: brightnessBinding, in: 0...1)
            }
        }
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { env.settingsStore.settings.displayBrightness[display.id] ?? 0.8 },
            set: { env.applyBrightness($0, to: display) }
        )
    }
}

// MARK: - CPU temperature

private struct TemperatureSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("CPU temperature") {
            Toggle("Show CPU temperature in the menu bar", isOn: s.binding(\.cpuTemperatureEnabled))
            Text("Adds a flame icon with the current CPU temperature, read from the Mac's sensors. It turns orange, then red, as the chip heats up.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if s.settings.cpuTemperatureEnabled {
                Toggle("Show in Fahrenheit", isOn: s.binding(\.temperatureFahrenheit))
            }
        }
    }
}

// MARK: - Window swipe

private struct WindowSwipeSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("Window swipe") {
            Toggle("Manage windows with a two-finger swipe on the title bar",
                   isOn: s.binding(\.windowSwipeEnabled))
            Text("Point at a window's title bar, then swipe two fingers: up to fill the screen, down to minimize.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if s.settings.windowSwipeEnabled {
                Toggle("Swipe left or right to snap to half-screen",
                       isOn: s.binding(\.windowSnapEnabled))
                Text("A left or right swipe aligns the window to that half of the current screen.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Text("Sensitivity")
                    Slider(value: s.binding(\.swipeSensitivity), in: 0...1)
                }
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Requires Accessibility permission.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                }
            }
        }
    }
}

// MARK: - Pinch gestures

private struct DockGesturesSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        let anyOn = s.settings.dockPinchQuitEnabled || s.settings.windowPinchCloseEnabled
        Section("Pinch gestures") {
            Toggle("Pinch a Dock icon to quit the app", isOn: s.binding(\.dockPinchQuitEnabled))
            Text("Point at an app's icon in the Dock and pinch-in (two fingers together) to quit it. Apps with unsaved work still get to ask first.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            Toggle("Pinch a window's title bar to close it", isOn: s.binding(\.windowPinchCloseEnabled))
            Text("Point at a window's title bar and pinch-in to close just that window (not the whole app).")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            if anyOn {
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Requires Accessibility permission.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                } else if !env.diagnostics.dockPinchActive {
                    Text("Trackpad not detected — this needs a Magic Trackpad or built-in trackpad.")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Notch reveal

private struct NotchRevealSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("Notch") {
            Toggle("Reveal menu bar icons hidden behind the notch", isOn: s.binding(\.notchRevealEnabled))
            Text("Move the pointer to the notch to reveal icons the notch is covering, then click one to open it. Built-in display only.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            if s.settings.notchRevealEnabled {
                if env.permissions.status(for: .screenRecording) != .granted {
                    HStack {
                        Text("Needs Screen Recording to show the hidden icons.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { _ = env.permissions.requestScreenRecording() }
                    }
                }
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Needs Accessibility to click a revealed icon.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                }
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Section("Permissions") {
            ForEach(PermissionKind.allCases, id: \.self) { kind in
                HStack {
                    Text(kind.displayName)
                    Spacer()
                    statusLabel(env.permissions.status(for: kind))
                    Button("Open Settings") { env.permissions.openSystemSettings(for: kind) }
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Text("Granted").foregroundStyle(.green).font(.system(size: 12))
        case .denied:
            Text("Denied").foregroundStyle(.red).font(.system(size: 12))
        case .notRequested:
            Text("Not requested").foregroundStyle(.secondary).font(.system(size: 12))
        }
    }
}

// MARK: - Status (live diagnostics)

private struct StatusSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let d = env.diagnostics
        Section("Status") {
            row("Window-swipe active", d.swipeTapInstalled,
                onText: "listening", offText: env.settingsStore.settings.windowSwipeEnabled ? "needs Accessibility" : "off")
            row("Brightness keys active", d.brightnessKeyTapInstalled,
                onText: "listening", offText: env.settingsStore.settings.brightnessEnabled ? "needs Accessibility" : "off")
            row("Dock pinch active", d.dockPinchActive,
                onText: "listening", offText: env.settingsStore.settings.dockPinchQuitEnabled ? "needs Accessibility / trackpad" : "off")
            HStack {
                Text("External displays")
                Spacer()
                Text("\(d.externalDisplayCount) screen(s), \(d.ddcServiceCount) DDC")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                Text("Next meeting")
                Spacer()
                Text(nextMeetingDescription).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text("\"Active\" means the feature is receiving input. If it says \"needs Accessibility\", grant it above — it switches to listening within a second, no relaunch.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var nextMeetingDescription: String {
        let now = env.now
        guard let m = QuackKit.MeetingSelection.currentOrNext(from: env.meetingStore.upcoming, now: now) else {
            return "none (\(env.meetingStore.upcoming.count) upcoming)"
        }
        let f = DateFormatter(); f.timeStyle = .medium; f.dateStyle = .none
        let secs = Int(m.start.timeIntervalSince(now))
        let state = m.isInProgress(at: now) ? "in progress" : (secs > 0 ? "in \(secs)s" : "started \(-secs)s ago")
        return "\(m.title)\nstarts \(f.string(from: m.start)) · \(state)"
    }

    private func row(_ title: String, _ on: Bool, onText: String, offText: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? .green : .secondary)
            Text(on ? onText : offText)
                .font(.system(size: 12)).foregroundStyle(on ? .green : .secondary)
        }
    }
}
