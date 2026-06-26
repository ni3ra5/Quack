import Foundation
import AppKit
import EventKit
import QuackKit

/// Drives `MeetingStore` refreshes: requests calendar access on start, refreshes
/// on a repeating timer, and reacts to `.EKEventStoreChanged`.
@MainActor
final class CalendarRefreshService: ManagedService {
    private let store: MeetingStore
    private let permissions: PermissionsManager
    private let interval: TimeInterval

    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(store: MeetingStore, permissions: PermissionsManager, interval: TimeInterval = 60) {
        self.store = store
        self.permissions = permissions
        self.interval = interval
    }

    func start() {
        Task { @MainActor in
            _ = await permissions.requestCalendarAccess()
            await store.refresh()
        }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.store.refresh() }
        }
        timer.tolerance = 30
        self.timer = timer

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.store.refresh() }
        }

        // Timers don't fire reliably across sleep — refresh on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.store.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        store.clear()
    }
}
