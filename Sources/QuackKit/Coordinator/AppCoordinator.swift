import Foundation
import Combine

/// Observes `SettingsStore` and starts/stops feature services as flags flip.
///
/// This guarantees no permission prompt fires for a disabled feature: a
/// service is only ever `start()`ed when its flag is on. Reminders depend on
/// the calendar feature, so they are gated on both flags.
@MainActor
public final class AppCoordinator {
    private let store: SettingsStore
    private let services: [Feature: ManagedService]
    private var running: Set<Feature> = []
    private var cancellable: AnyCancellable?

    public init(store: SettingsStore, services: [Feature: ManagedService]) {
        self.store = store
        self.services = services
    }

    /// Begins observing settings and reconciles once immediately.
    public func activate() {
        reconcile(with: store.settings)
        // Deliver synchronously: settings are always mutated on the main thread,
        // so reconciliation runs inline with the change (and tests can assert it).
        cancellable = store.$settings
            .dropFirst()
            .sink { [weak self] newValue in
                self?.reconcile(with: newValue)
            }
    }

    public func deactivate() {
        cancellable = nil
        for feature in running {
            services[feature]?.stop()
        }
        running.removeAll()
    }

    /// Whether a feature's service should currently be running. Reminders
    /// additionally require the calendar feature.
    public func shouldRun(_ feature: Feature, in settings: QuackSettings) -> Bool {
        switch feature {
        case .reminders:
            return settings.remindersEnabled && settings.calendarEnabled
        default:
            return feature.isEnabled(in: settings)
        }
    }

    private func reconcile(with settings: QuackSettings) {
        for (feature, service) in services {
            let want = shouldRun(feature, in: settings)
            let isRunning = running.contains(feature)
            if want && !isRunning {
                service.start()
                running.insert(feature)
            } else if !want && isRunning {
                service.stop()
                running.remove(feature)
            }
        }
    }

    /// Test introspection: features whose service is currently started.
    public var runningFeatures: Set<Feature> { running }
}
