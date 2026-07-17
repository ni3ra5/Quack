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

    // A reminder fires if "now" is within this window past its scheduled instant
    // — so a just-launched app doesn't replay long-past reminders, and a brief
    // sleep doesn't lose one.
    private let fireWindow: TimeInterval = 150

    init(store: MeetingStore, settings: SettingsStore, toasts: ToastPresenter, sound: QuackSound) {
        self.store = store
        self.settings = settings
        self.toasts = toasts
        self.sound = sound
    }

    func start() {
        active = true
        // Don't replay reminders whose moment already passed before we started.
        primeAlreadyPassed(now: Date())

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
        cancellables.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        nextTimer?.invalidate()
        nextTimer = nil
        fired.removeAll()
    }

    private func leadID(_ meeting: MeetingEvent, _ lead: Int) -> String { "\(meeting.id)-\(lead)" }
    private func startID(_ meeting: MeetingEvent) -> String { "\(meeting.id)-start" }

    /// Marks reminders that are no longer worth showing as "fired" so a launch
    /// doesn't replay them. An advance reminder is only suppressed once its
    /// meeting has already started (a meeting still in the future is always worth
    /// a heads-up on launch — see the catch-up in `check()`). The "join now"
    /// start reminder is suppressed once its meeting started more than a fire
    /// window ago, so a fresh launch still surfaces a just-started meeting.
    private func primeAlreadyPassed(now: Date) {
        for meeting in store.upcoming where !meeting.isAllDay {
            if now >= meeting.start {
                for lead in leads { fired.insert(leadID(meeting, lead)) }
            }
            if now >= meeting.start.addingTimeInterval(fireWindow) {
                fired.insert(startID(meeting))
            }
        }
    }

    private var leads: [Int] { settings.settings.reminderLeadMinutes.filter { $0 > 0 } }

    private func check() {
        guard active else { return }
        let now = Date()
        for meeting in store.upcoming where !meeting.isAllDay {
            // Fire an advance reminder whenever its instant has passed and the
            // meeting hasn't started — NOT only inside a tight window. This makes
            // reminders survive throttled/coalesced timers (App Nap on this
            // background agent) and launches: a late check still delivers. If
            // several leads elapsed together (e.g. after a nap), collapse them
            // into one toast and label it with the ACTUAL time remaining.
            let passed = leads.filter { lead in
                let fire = meeting.start.addingTimeInterval(-Double(lead) * 60)
                return now >= fire && now < meeting.start && !fired.contains(leadID(meeting, lead))
            }
            if !passed.isEmpty {
                for lead in passed { fired.insert(leadID(meeting, lead)) }
                showReminder(meeting, now: now)
            }
            let sid = startID(meeting)
            if settings.settings.remindAtStart,
               !fired.contains(sid), now >= meeting.start, now < meeting.start.addingTimeInterval(fireWindow) {
                fired.insert(sid)
                showStart(meeting)
                sound.play(NotificationSound.from(settings.settings.joinAlertSound))
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

        var soonest: Date?
        func consider(_ date: Date) {
            guard date > now else { return }
            soonest = min(soonest ?? date, date)
        }
        for meeting in store.upcoming where !meeting.isAllDay {
            for lead in leads where !fired.contains(leadID(meeting, lead)) {
                consider(meeting.start.addingTimeInterval(-Double(lead) * 60))
            }
            if !fired.contains(startID(meeting)) { consider(meeting.start) }
        }
        guard let target = soonest else { return }

        // +0.2s so the timer fires just past the instant (now >= start holds).
        let interval = max(0.2, target.timeIntervalSince(now) + 0.2)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        nextTimer = timer
    }

    private func showReminder(_ meeting: MeetingEvent, now: Date) {
        // Label with the real minutes remaining, rounded up, so a catch-up toast
        // fired late (after a nap) reads correctly rather than showing the
        // configured lead. Never below 1.
        let minutes = max(1, Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up)))
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
