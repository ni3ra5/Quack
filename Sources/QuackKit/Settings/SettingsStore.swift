import Foundation
import Combine

/// Minimal key-value persistence abstraction so `SettingsStore` can be unit
/// tested against an in-memory backend instead of the real `UserDefaults`.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    public func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }
    public func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }
}

/// In-memory backend for tests.
public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { storage[key] }
    public func set(_ data: Data?, forKey key: String) {
        if let data { storage[key] = data } else { storage[key] = nil }
    }
}

/// Observable, persisted settings. Loads once on init, writes through on every
/// mutation, and publishes changes via `objectWillChange` / `$settings`.
public final class SettingsStore: ObservableObject {
    public static let defaultsKey = "com.quack.settings.v1"

    @Published public private(set) var settings: QuackSettings

    private let backing: KeyValueStore
    private let key: String

    public init(backing: KeyValueStore = UserDefaults.standard, key: String = SettingsStore.defaultsKey) {
        self.backing = backing
        self.key = key
        if let data = backing.data(forKey: key),
           let decoded = try? JSONDecoder().decode(QuackSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = QuackSettings()
        }
    }

    /// Mutate settings in place and persist. The closure receives `inout` so
    /// callers can change several fields atomically.
    public func update(_ mutate: (inout QuackSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        persist()
    }

    /// Replace the whole settings value.
    public func replace(with newValue: QuackSettings) {
        guard newValue != settings else { return }
        settings = newValue
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        backing.set(data, forKey: key)
    }
}
