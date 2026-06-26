import SwiftUI
import QuackKit

/// The feature groups shown as tabs in the settings window.
enum SettingsTab: String, CaseIterable {
    case calendar, reminders, display, windows, permissions

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .display: return "Display"
        case .windows: return "Windows"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .reminders: return "bell.badge"
        case .display: return "sun.max"
        case .windows: return "macwindow.on.rectangle"
        case .permissions: return "lock.shield"
        }
    }
}

/// The whole settings window: an app header (icon, name, description,
/// launch-at-login), a tab strip, and the selected pane.
struct SettingsRootView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var tab: SettingsTab = .calendar
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabStrip
            Divider()
            SettingsPane(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 640)
        .tint(.accentColor)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled; env.permissions.refreshAll() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quack").font(.title2).bold()
                Text("Meeting countdowns, reminders, monitor brightness & window shortcuts.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("Launch Quack at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.set($0) }
                .toggleStyle(.switch)
                .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 17))
                        Text(item.title).font(.caption)
                    }
                    .frame(width: 78, height: 50)
                    .foregroundStyle(tab == item ? Color.accentColor : Color.primary)
                    .background(tab == item ? Color.accentColor.opacity(0.18) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// One settings pane (a grouped Form).
struct SettingsPane: View {
    let tab: SettingsTab
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Form {
            switch tab {
            case .calendar: CalendarSection()
            case .reminders: RemindersSection()
            case .display: BrightnessSection()
            case .windows:
                WindowSwipeSection()
                KeyboardShortcutsSection()
            case .permissions:
                PermissionsSection()
                StatusSection()
            }
        }
        .formStyle(.grouped)
    }
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
        } footer: {
            Text("When off, the menu bar shows just the duck.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Toggle("Show calendar events", isOn: s.binding(\.calendarEnabled))
        }

        if s.settings.calendarEnabled {
            if env.permissions.status(for: .calendar) != .granted {
                Section {
                    HStack {
                        Text("Calendar access is needed to read your events.")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Grant") { env.requestCalendarAccess() }
                    }
                }
            } else {
                // One card per account; children are dividers within the card.
                ForEach(accounts) { account in
                    Section {
                        Toggle(isOn: accountBinding(account)) {
                            Text(account.title).fontWeight(.semibold)
                        }
                        // Children only show while the account is on.
                        if isAccountOn(account) {
                            ForEach(account.calendars) { cal in
                                Toggle(cal.title, isOn: calendarBinding(cal.id))
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }

                if accounts.isEmpty {
                    Section { Text("No calendars found.").font(.caption).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Add or remove accounts…") { env.openInternetAccounts() }
                    Button("Refresh calendars") { accounts = env.availableAccounts() }
                    Text("Accounts are added in System Settings → Internet Accounts.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Label {
                        Text("Edits made in another app (Google, Notion, etc.) appear after macOS syncs them. If they're slow, shorten **Calendar app → Settings → Accounts → Refresh Calendars**.")
                            .font(.caption).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Tip")
                }
            }
        }
      }
      .onAppear { accounts = env.availableAccounts() }
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
                    Text("Pick at least one modifier.").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("\(modifierString) + arrows:  ↑ maximize / monitor above · ↓ small / monitor below · ← left half / monitor left · → right half / monitor right. Press again to move to the adjacent monitor.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Requires Accessibility permission.").font(.caption).foregroundStyle(.orange)
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
    private let commonLeads = [20, 10, 5, 2]

    var body: some View {
        let s = env.settingsStore
        Section("Reminders") {
            Toggle("Meeting reminders", isOn: s.binding(\.remindersEnabled))
            if s.settings.remindersEnabled {
                if !s.settings.calendarEnabled {
                    Text("Requires Calendar to be enabled.")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(commonLeads, id: \.self) { lead in
                    Toggle("\(lead) minutes before", isOn: leadBinding(lead))
                }
            }
        }
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
                .font(.caption).foregroundStyle(.secondary)

            if !env.brightnessController.isSupportedPlatform {
                Text("Brightness control is unavailable on this Mac.")
                    .font(.caption).foregroundStyle(.orange)
            } else if s.settings.brightnessEnabled {
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("F1 / F2 routing needs Accessibility permission (the slider still works without it).")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                }
                Stepper("Step: \(s.settings.brightnessStepPercent)%",
                        value: s.binding(\.brightnessStepPercent), in: 1...50, step: 1)
                Toggle("Dim the inactive display", isOn: s.binding(\.dimInactiveDisplay))
                if env.brightnessController.displays.isEmpty {
                    Text("No external displays detected.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    .font(.caption)
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

// MARK: - Window swipe

private struct WindowSwipeSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("Window swipe") {
            Toggle("Fling windows to another monitor with a two-finger swipe",
                   isOn: s.binding(\.windowSwipeEnabled))
            Text("Point at a window's title bar, then swipe two fingers on the trackpad toward the other monitor. Works both directions.")
                .font(.caption).foregroundStyle(.secondary)
            if s.settings.windowSwipeEnabled {
                Toggle("Snap to half-screen when there's no monitor that way",
                       isOn: s.binding(\.windowSnapEnabled))
                Text("Swiping left/right with no monitor in that direction aligns the window to that half of the screen.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Sensitivity")
                    Slider(value: s.binding(\.swipeSensitivity), in: 0...1)
                }
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Requires Accessibility permission.")
                            .font(.caption).foregroundStyle(.orange)
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
            Text("Granted").foregroundStyle(.green).font(.caption)
        case .denied:
            Text("Denied").foregroundStyle(.red).font(.caption)
        case .notRequested:
            Text("Not requested").foregroundStyle(.secondary).font(.caption)
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
            HStack {
                Text("External displays")
                Spacer()
                Text("\(d.externalDisplayCount) screen(s), \(d.ddcServiceCount) DDC")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                Text("Next meeting")
                Spacer()
                Text(nextMeetingDescription).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text("\"Active\" means the feature is receiving input. If it says \"needs Accessibility\", grant it above — it switches to listening within a second, no relaunch.")
                .font(.caption).foregroundStyle(.secondary)
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
                .font(.caption).foregroundStyle(on ? .green : .secondary)
        }
    }
}
