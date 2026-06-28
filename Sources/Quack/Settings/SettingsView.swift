import SwiftUI
import QuackKit

/// The feature groups shown as tabs in the settings window.
enum SettingsTab: String, CaseIterable {
    case general, calendar, display, temperature, windows, permissions

    var title: String {
        switch self {
        case .general: return "General"
        case .calendar: return "Calendar"
        case .display: return "Display"
        case .temperature: return "CPU"
        case .windows: return "Windows"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .calendar: return "calendar"
        case .display: return "sun.max"
        case .temperature: return "thermometer.medium"
        case .windows: return "macwindow.on.rectangle"
        case .permissions: return "lock.shield"
        }
    }
}

/// The whole settings window: an app header (icon, name, description,
/// launch-at-login), a tab strip, and the selected pane.
struct SettingsRootView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabStrip
            Divider()
            SettingsPane(tab: env.settingsTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 640)
        .font(.system(size: 14))   // bump the base text a little across the window
        .background(Color(white: 0.07))
        .tint(.accentColor)
        .onAppear { env.permissions.refreshAll() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quack").font(.title2).bold()
                Text("All shortcuts in one app. Quack Quack!")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { item in
                Button { env.settingsTab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 17))
                        Text(item.title).font(.system(size: 12))
                    }
                    .frame(width: 78, height: 50)
                    .foregroundStyle(env.settingsTab == item ? Color.accentColor : Color.primary)
                    .background(env.settingsTab == item ? Color.accentColor.opacity(0.18) : .clear)
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
            case .general: GeneralSection()
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
            case .permissions:
                PermissionsSection()
                StatusSection()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // let the darker window bg show through
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

// MARK: - General

private struct GeneralSection: View {
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
        Section {
            Button("Quit Quack") { NSApp.terminate(nil) }
        }
      }
      .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
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

// MARK: - Dock gestures

private struct DockGesturesSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("Dock gestures") {
            Toggle("Pinch a Dock icon to quit the app", isOn: s.binding(\.dockPinchQuitEnabled))
            Text("Point at an app's icon in the Dock and pinch-in (two fingers together) on the trackpad to quit it. Apps with unsaved work still get to ask before closing.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if s.settings.dockPinchQuitEnabled {
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
