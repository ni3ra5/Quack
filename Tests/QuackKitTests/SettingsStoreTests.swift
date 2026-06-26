import Testing
import Foundation
@testable import QuackKit

@Suite struct SettingsTests {

    @Test func defaults() {
        let s = QuackSettings()
        #expect(s.calendarEnabled)
        #expect(s.remindersEnabled)
        #expect(s.menuBarCountdownEnabled)
        #expect(!s.brightnessEnabled)
        #expect(!s.windowSwipeEnabled)
        #expect(s.reminderLeadMinutes == [10, 5])
        #expect(abs(s.swipeSensitivity - 0.5) < 0.0001)
    }

    @Test func encodeDecodeRoundTrip() throws {
        var s = QuackSettings()
        s.brightnessEnabled = true
        s.reminderLeadMinutes = [20, 10, 5]
        s.selectedCalendarIDs = ["cal-1", "cal-2"]
        s.displayBrightness = ["DELL-1": 0.7]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(QuackSettings.self, from: data)
        #expect(s == decoded)
    }

    @Test func decodingMissingFieldsFallsBackToDefaults() throws {
        let json = #"{"brightnessEnabled": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QuackSettings.self, from: json)
        #expect(decoded.brightnessEnabled)
        #expect(decoded.reminderLeadMinutes == [10, 5])
        #expect(decoded.calendarEnabled)
        #expect(decoded.syncAllCalendars)   // new field defaults true for old blobs
    }

    @Test func persistsAndReloadsFromBacking() {
        let backing = InMemoryKeyValueStore()
        let store = SettingsStore(backing: backing, key: "test")
        store.update { $0.brightnessEnabled = true; $0.swipeSensitivity = 0.9 }

        let reloaded = SettingsStore(backing: backing, key: "test")
        #expect(reloaded.settings.brightnessEnabled)
        #expect(abs(reloaded.settings.swipeSensitivity - 0.9) < 0.0001)
    }

    @Test func updatePublishesOnlyOnRealChange() {
        let store = SettingsStore(backing: InMemoryKeyValueStore(), key: "test")
        var published = 0
        let c = store.$settings.dropFirst().sink { _ in published += 1 }
        store.update { $0.windowSwipeEnabled = true }
        store.update { $0.windowSwipeEnabled = true }   // no-op -> no publish
        store.update { $0.windowSwipeEnabled = false }
        c.cancel()
        #expect(published == 2)
    }
}
