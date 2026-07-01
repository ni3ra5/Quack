import Testing
@testable import QuackKit

@Suite struct PermissionStatusMapperTests {
    @Test func calendarMapping() {
        #expect(PermissionStatusMapper.calendar(fromEventKitRawValue: 0) == .notRequested)
        #expect(PermissionStatusMapper.calendar(fromEventKitRawValue: 1) == .denied)   // restricted
        #expect(PermissionStatusMapper.calendar(fromEventKitRawValue: 2) == .denied)   // denied
        #expect(PermissionStatusMapper.calendar(fromEventKitRawValue: 3) == .granted)  // authorized
        #expect(PermissionStatusMapper.calendar(fromEventKitRawValue: 4) == .denied)   // writeOnly
        #expect(PermissionStatusMapper.calendar(fromEventKitRawValue: 5) == .granted)  // fullAccess
    }

    @Test func notificationsMapping() {
        #expect(PermissionStatusMapper.notifications(fromUNRawValue: 0) == .notRequested)
        #expect(PermissionStatusMapper.notifications(fromUNRawValue: 1) == .denied)
        #expect(PermissionStatusMapper.notifications(fromUNRawValue: 2) == .granted)
        #expect(PermissionStatusMapper.notifications(fromUNRawValue: 3) == .granted)   // provisional
    }

    @Test func accessibilityMapping() {
        #expect(PermissionStatusMapper.accessibility(isTrusted: true) == .granted)
        #expect(PermissionStatusMapper.accessibility(isTrusted: false) == .notRequested)
    }

    @Test func screenRecordingMapping() {
        #expect(PermissionStatusMapper.screenRecording(hasAccess: true) == .granted)
        #expect(PermissionStatusMapper.screenRecording(hasAccess: false) == .notRequested)
    }

    @Test func screenRecordingIsAKnownPermissionKind() {
        #expect(PermissionKind.allCases.contains(.screenRecording))
        #expect(PermissionKind.screenRecording.displayName == "Screen Recording")
    }
}

@MainActor
private final class SpyService: ManagedService {
    var startCount = 0
    var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@Suite @MainActor struct AppCoordinatorTests {

    private func make(_ initial: QuackSettings) -> (AppCoordinator, SettingsStore, [Feature: SpyService]) {
        let store = SettingsStore(backing: InMemoryKeyValueStore(), key: "t")
        store.replace(with: initial)
        let services: [Feature: SpyService] = [
            .calendar: SpyService(), .reminders: SpyService(), .menuBarCountdown: SpyService(),
            .brightness: SpyService(), .windowSwipe: SpyService(),
        ]
        let coord = AppCoordinator(store: store, services: services.mapValues { $0 as ManagedService })
        return (coord, store, services)
    }

    @Test func startsOnlyEnabledFeaturesOnActivate() {
        var s = QuackSettings()
        s.brightnessEnabled = false
        s.windowSwipeEnabled = false
        let (coord, _, services) = make(s)
        coord.activate()
        #expect(services[.calendar]!.startCount == 1)
        #expect(services[.reminders]!.startCount == 1)
        #expect(services[.menuBarCountdown]!.startCount == 1)
        #expect(services[.brightness]!.startCount == 0)
        #expect(services[.windowSwipe]!.startCount == 0)
    }

    @Test func flipFlagStartsAndStopsService() {
        var s = QuackSettings()
        s.brightnessEnabled = false
        let (coord, store, services) = make(s)
        coord.activate()
        #expect(services[.brightness]!.startCount == 0)

        store.update { $0.brightnessEnabled = true }
        #expect(services[.brightness]!.startCount == 1)

        store.update { $0.brightnessEnabled = false }
        #expect(services[.brightness]!.stopCount == 1)
    }

    @Test func remindersRequireCalendar() {
        var s = QuackSettings()
        s.calendarEnabled = false
        s.remindersEnabled = true
        let (coord, store, services) = make(s)
        coord.activate()
        #expect(services[.reminders]!.startCount == 0)   // calendar off -> reminders off

        store.update { $0.calendarEnabled = true }
        #expect(services[.reminders]!.startCount == 1)
    }
}
