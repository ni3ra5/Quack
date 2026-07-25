import Foundation
import Combine
import QuackKit

/// Fires in-app toast alerts for upcoming meetings (Notion-Calendar style): an
/// advance reminder at each configured lead time, plus a "join now" toast at the
/// start that also plays the quack sound.
///
/// Uses a steady poll (not per-reminder timers): every tick it checks whether
/// any meeting has just crossed a lead/start threshold and fires once. This is
/// robust against the meeting list refreshing frequently (which would otherwise
/// cancel/recreate pending timers) and against brief sleeps.
@MainActor
final class ReminderScheduler: ManagedService {
    private let store: MeetingStore
    private let settings: SettingsStore
    private let toasts: ToastPresenter
    private let sound: QuackSound

    private var cancellables: Set<AnyCancellable> = []
    private var pollTimer: Timer?
    private var nextTimer: Timer?   // one-shot, fires exactly at the next reminder instant
    private var fired: Set<String> = []   // reminder identifiers already shown
    private var active = false
    // Holds an App Nap opt-out while reminders are on. Without it, macOS throttles
    // this background agent's timers when idle, so the 15s poll / one-shot could
    // skip a reminder's moment entirely. `.userInitiatedAllowingIdleSystemSleep`
    // keeps the timers punctual but still lets the Mac sleep when idle.
    private var activityToken: NSObjectProtocol?

    init(store: MeetingStore, settings: SettingsStore, toasts: ToastPresenter, sound: QuackSound) {
        self.store = store
        self.settings = settings
        self.toasts = toasts
        self.sound = sound
    }

    func start() {
        active = true
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Deliver meeting reminders on time"
        )

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Also check immediately when the meeting list changes.
        store.$upcoming
            .sink { [weak self] _ in self?.check() }
            .store(in: &cancellables)
        check()
    }

    func stop() {
        active = false
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        activityToken = nil
        cancellables.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        nextTimer?.invalidate()
        nextTimer = nil
        fired.removeAll()
    }

    private var leads: [Int] { settings.settings.reminderLeadMinutes }

    /// Delivers whatever `ReminderEngine` says is due now, records it as fired,
    /// then arms a one-shot timer for the next instant. All firing rules live in
    /// the (unit-tested) engine; this method only presents the results.
    private func check() {
        guard active else { return }
        let now = Date()
        let due = ReminderEngine.due(
            meetings: store.upcoming, leads: leads,
            remindAtStart: settings.settings.remindAtStart, now: now, fired: fired
        )
        for item in due {
            item.keys.forEach { fired.insert($0) }
            switch item.kind {
            case .advance(let minutes): showReminder(item.meeting, minutesRemaining: minutes)
            case .start: showStart(item.meeting)
            }
        }
        scheduleNext(now: now)
    }

    /// Schedules a precise one-shot timer for the soonest not-yet-fired reminder
    /// instant, so toasts fire on time instead of waiting up to a full poll
    /// interval. The 15s poll remains as a safety net (sleep/wake, missed fires).
    private func scheduleNext(now: Date) {
        nextTimer?.invalidate()
        nextTimer = nil
        guard let target = ReminderEngine.nextInstant(
            meetings: store.upcoming, leads: leads,
            remindAtStart: settings.settings.remindAtStart, now: now, fired: fired
        ) else { return }

        // +0.2s so the timer fires just past the instant (now >= start holds).
        let interval = max(0.2, target.timeIntervalSince(now) + 0.2)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        nextTimer = timer
    }

    private func showReminder(_ meeting: MeetingEvent, minutesRemaining minutes: Int) {
        Log.reminders.log("advance reminder: \(meeting.title, privacy: .public) in \(minutes)m")
        let url = MeetingURLParser.joinURL(for: meeting)
        // Only the final 1-minute heads-up offers Join — earlier ones are plain
        // notifications that auto-dismiss.
        let joinable = minutes <= 1
        toasts.show(ToastItem(
            title: meeting.title,
            relativeText: joinable ? "in 1 min · join now" : "in \(minutes) min",
            timeRange: Self.timeRange(meeting.start, meeting.end),
            colorHex: meeting.calendarColorHex,
            joinURL: url,
            provider: MeetingProvider(url: url),
            joinable: joinable,
            isStart: false
        ), dismissAfter: joinable ? nil : 8)   // joinable stays; notifications auto-dismiss
        // 1-minute heads-up uses the join-alert sound; 20/10/5 use the notification sound.
        let soundID = joinable ? settings.settings.joinAlertSound : settings.settings.notificationSound
        sound.play(NotificationSound.from(soundID))
    }

    private func showStart(_ meeting: MeetingEvent) {
        Log.reminders.log("start reminder: \(meeting.title, privacy: .public)")
        let url = MeetingURLParser.joinURL(for: meeting)
        toasts.show(ToastItem(
            title: meeting.title,
            relativeText: "now",
            timeRange: Self.timeRange(meeting.start, meeting.end),
            colorHex: meeting.calendarColorHex,
            joinURL: url,
            provider: MeetingProvider(url: url),
            joinable: true,
            isStart: true
        ), dismissAfter: nil)   // stays until the user joins or dismisses
        sound.play(NotificationSound.from(settings.settings.joinAlertSound))
    }

    /// "4:22 – 5:07 PM" — the AM/PM marker is dropped from the start time when
    /// both ends share it, matching how calendars render a time range.
    private static func timeRange(_ start: Date, _ end: Date) -> String {
        let period = DateFormatter(); period.dateFormat = "a"
        let samePeriod = period.string(from: start) == period.string(from: end)
        let startFmt = DateFormatter(); startFmt.dateFormat = samePeriod ? "h:mm" : "h:mm a"
        let endFmt = DateFormatter(); endFmt.dateFormat = "h:mm a"
        return "\(startFmt.string(from: start)) – \(endFmt.string(from: end))"
    }
}
