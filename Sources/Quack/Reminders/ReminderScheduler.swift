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
        fired.removeAll()
    }

    private func leadID(_ meeting: MeetingEvent, _ lead: Int) -> String { "\(meeting.id)-\(lead)" }
    private func startID(_ meeting: MeetingEvent) -> String { "\(meeting.id)-start" }

    /// Marks reminders whose instant is already in the past as "fired" so we
    /// don't replay them on launch.
    private func primeAlreadyPassed(now: Date) {
        for meeting in store.upcoming where !meeting.isAllDay {
            for lead in leads {
                if meeting.start.addingTimeInterval(-Double(lead) * 60) <= now { fired.insert(leadID(meeting, lead)) }
            }
            if meeting.start <= now { fired.insert(startID(meeting)) }
        }
    }

    private var leads: [Int] { settings.settings.reminderLeadMinutes.filter { $0 > 0 } }

    private func check() {
        guard active else { return }
        let now = Date()
        for meeting in store.upcoming where !meeting.isAllDay {
            for lead in leads {
                let fire = meeting.start.addingTimeInterval(-Double(lead) * 60)
                let id = leadID(meeting, lead)
                if !fired.contains(id), now >= fire, now < fire.addingTimeInterval(fireWindow), now < meeting.start {
                    fired.insert(id)
                    showReminder(meeting, leadMinutes: lead)
                }
            }
            let sid = startID(meeting)
            if !fired.contains(sid), now >= meeting.start, now < meeting.start.addingTimeInterval(fireWindow) {
                fired.insert(sid)
                showStart(meeting)
                sound.play()
            }
        }
    }

    private func showReminder(_ meeting: MeetingEvent, leadMinutes: Int) {
        Log.reminders.log("advance reminder: \(meeting.title, privacy: .public) in \(leadMinutes)m")
        toasts.show(ToastItem(
            title: meeting.title, subtitle: "in \(leadMinutes) min",
            colorHex: meeting.calendarColorHex,
            joinURL: MeetingURLParser.joinURL(for: meeting), isStart: false
        ), dismissAfter: 8)
    }

    private func showStart(_ meeting: MeetingEvent) {
        Log.reminders.log("start reminder: \(meeting.title, privacy: .public)")
        toasts.show(ToastItem(
            title: meeting.title, subtitle: "Starting now",
            colorHex: meeting.calendarColorHex,
            joinURL: MeetingURLParser.joinURL(for: meeting), isStart: true
        ), dismissAfter: 25)
    }
}
