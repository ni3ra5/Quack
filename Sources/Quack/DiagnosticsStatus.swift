import Foundation
import Combine

/// Live runtime status the Settings window surfaces so the user can see exactly
/// what is and isn't working (event taps installed, displays detected) without
/// digging through logs.
@MainActor
final class DiagnosticsStatus: ObservableObject {
    @Published var swipeTapInstalled = false
    @Published var brightnessKeyTapInstalled = false
    @Published var externalDisplayCount = 0
    @Published var ddcServiceCount = 0
}
