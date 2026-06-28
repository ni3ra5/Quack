import SwiftUI
import AppKit
import Combine
import QuackKit

/// Central composition root. Owns the settings, the meeting store, every live
/// service, and the coordinator that starts/stops services as flags flip.
/// Injected into the SwiftUI environment as a single `ObservableObject`.
@MainActor
final class AppEnvironment: ObservableObject {
    let settingsStore: SettingsStore
    let permissions: PermissionsManager
    let meetingStore: MeetingStore
    let diagnostics = DiagnosticsStatus()

    /// A reliably-ticking clock that drives the menu-bar countdown. A
    /// `Timer.publish` placed inside a `MenuBarExtra` label does not fire
    /// dependably, which froze the countdown; this timer lives on the main
    /// run loop in `.common` mode so it keeps firing during menu tracking too.
    @Published var now = Date()
    /// The currently selected settings tab (lifted here so features can deep-link
    /// to a specific tab, e.g. the temperature popover → Display).
    @Published var settingsTab: SettingsTab = .general
    private var clockTimer: Timer?
    private var activeObserver: NSObjectProtocol?

    private let eventKitProvider: EventKitProvider
    let brightnessController: BrightnessController
    private let toasts = ToastPresenter()
    private let quackSound = QuackSound()
    private let settingsWindow = SettingsWindowController()

    private let calendarService: CalendarRefreshService
    private let reminderScheduler: ReminderScheduler
    private let cursorService: CursorBrightnessService
    private let gestureService: GestureMonitor
    private let hotkeyService: HotkeyMonitor
    private let dockPinchService: DockPinchMonitor
    private let temperatureService: TemperatureStatusItem

    private let coordinator: AppCoordinator
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = SettingsStore()
        // Calendar is always on now (its toggle was removed); it powers the
        // countdown, reminders, and the dropdown list.
        settings.update { $0.calendarEnabled = true }
        let permissions = PermissionsManager()
        let provider = EventKitProvider(permissions: permissions)
        let store = MeetingStore(
            provider: provider,
            calendarIDs: {
                settings.settings.syncAllCalendars ? [] : settings.settings.selectedCalendarIDs
            }
        )
        let brightness = BrightnessController()

        self.settingsStore = settings
        self.permissions = permissions
        self.eventKitProvider = provider
        self.meetingStore = store
        self.brightnessController = brightness

        self.calendarService = CalendarRefreshService(store: store, permissions: permissions)
        self.reminderScheduler = ReminderScheduler(store: store, settings: settings, toasts: toasts, sound: quackSound)
        self.cursorService = CursorBrightnessService(controller: brightness, settings: settings, permissions: permissions, diagnostics: diagnostics)
        self.gestureService = GestureMonitor(settings: settings, permissions: permissions, diagnostics: diagnostics)
        self.hotkeyService = HotkeyMonitor(settings: settings, permissions: permissions)
        self.dockPinchService = DockPinchMonitor(settings: settings, permissions: permissions, diagnostics: diagnostics)
        self.temperatureService = TemperatureStatusItem(settings: settings)

        let services: [Feature: ManagedService] = [
            .calendar: calendarService,
            .reminders: reminderScheduler,
            .menuBarCountdown: NullService(),   // title is driven reactively; no side effects
            .brightness: cursorService,
            .windowSwipe: gestureService,
            .windowShortcuts: hotkeyService,
            .dockPinch: dockPinchService,
            .temperature: temperatureService,
        ]
        self.coordinator = AppCoordinator(store: settings, services: services)
        temperatureService.onOpenSettings = { [weak self] in self?.showSettings(selecting: .temperature) }

        // Re-forward nested ObservableObject changes so SwiftUI views observing
        // `AppEnvironment` refresh when settings / meetings / permissions change.
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        permissions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        brightness.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        diagnostics.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        permissions.refreshAll()
        coordinator.activate()

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            // Fires on the main run loop it's added to.
            MainActor.assumeIsolated { self?.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer

        // Re-check permissions and reload the calendar when returning to the app
        // (e.g. after granting access in System Settings).
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.permissions.refreshAll()
                self?.refreshCalendarNow()
            }
        }
    }

    /// Event calendars available for the settings picker (empty if no access).
    func availableCalendars() -> [(id: String, title: String)] {
        eventKitProvider.availableCalendars()
    }

    /// Calendar accounts (grouped) for the settings UI.
    func availableAccounts() -> [CalendarAccountInfo] {
        eventKitProvider.availableAccounts()
    }

    /// Requests calendar access (used when the picker is empty because access
    /// has not been granted yet), then refreshes status.
    func requestCalendarAccess() {
        Task { @MainActor in
            let granted = await permissions.requestCalendarAccess()
            // If the system didn't (or couldn't) prompt — already shown this
            // session, or previously denied — send the user to System Settings
            // so the button is never a dead end.
            if !granted { permissions.openCalendarSettings() }
            await meetingStore.refresh()
            objectWillChange.send()
        }
    }

    /// Plays a sound for the settings preview button.
    func previewSound(_ sound: NotificationSound) {
        quackSound.play(sound)
    }

    /// Shows a sample "join now" toast so the user can confirm reminders appear
    /// (independent of whether a real meeting is currently due).
    func previewToast() {
        let url = URL(string: "https://meet.google.com/abc-defg-hij")
        let now = Date()
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        toasts.show(ToastItem(
            title: "Preview meeting",
            relativeText: "now",
            timeRange: "\(f.string(from: now)) – \(f.string(from: now.addingTimeInterval(1800)))",
            colorHex: nil,
            joinURL: url,
            provider: MeetingProvider(url: url),
            joinable: true,
            isStart: true
        ), dismissAfter: nil)   // mirror the real join-now toast: stays until dismissed
        quackSound.play(NotificationSound.from(settingsStore.settings.joinAlertSound))
    }

    /// Shows a sample advance-reminder toast (plain notification, no Join button,
    /// auto-dismiss) — what the 20/10/5-minute reminders look like.
    func previewReminderToast() {
        let url = URL(string: "https://meet.google.com/abc-defg-hij")
        let now = Date()
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        toasts.show(ToastItem(
            title: "Preview meeting",
            relativeText: "in 10 min",
            timeRange: "\(f.string(from: now.addingTimeInterval(600))) – \(f.string(from: now.addingTimeInterval(2400)))",
            colorHex: nil,
            joinURL: url,
            provider: MeetingProvider(url: url),
            joinable: false,
            isStart: false
        ), dismissAfter: 6)
        quackSound.play(NotificationSound.from(settingsStore.settings.notificationSound))
    }

    /// Re-reads the calendar now (e.g. when the menu opens) so the list is never
    /// showing stale/empty data.
    func refreshCalendarNow() {
        guard settingsStore.settings.calendarEnabled else { return }
        Task { @MainActor in
            await meetingStore.refresh()
            // The fetch above also asks macOS to sync remote sources, which is
            // async — so fetch again a few seconds later to pick up an edit that
            // had just synced from the cloud (Google/iCloud).
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await meetingStore.refresh()
        }
    }

    /// Opens (and focuses) the Quack settings window, optionally selecting a tab.
    func showSettings(selecting tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        settingsWindow.show(env: self)
    }

    /// Opens System Settings → Internet Accounts, where macOS calendar accounts
    /// are added or removed (apps cannot do this directly).
    func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.internetaccounts") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Applies a brightness change immediately and persists it.
    func applyBrightness(_ fraction: Double, to display: ControllableDisplay) {
        settingsStore.update { $0.displayBrightness[display.id] = fraction }
        brightnessController.apply(fraction: fraction, to: display)
    }
}

/// A no-op service used for features that are purely reactive (the menu-bar
/// countdown is rendered from `MeetingStore`, so it needs no lifecycle).
@MainActor
private final class NullService: ManagedService {
    func start() {}
    func stop() {}
}
