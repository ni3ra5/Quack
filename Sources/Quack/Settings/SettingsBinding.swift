import SwiftUI
import QuackKit

extension SettingsStore {
    /// A two-way SwiftUI binding to a single settings field, persisting on write.
    func binding<T>(_ keyPath: WritableKeyPath<QuackSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
