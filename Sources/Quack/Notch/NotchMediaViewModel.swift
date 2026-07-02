import AppKit
import Combine
import MediaRemoteAdapter

@MainActor
final class NotchMediaViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var track: TrackInfo?
    /// The real notch height for this screen (from `cocoaNotchRect.height`) — the
    /// view pads content below this so it never renders under the physical cutout.
    @Published var contentTopInset: CGFloat = 0

    var onHoverChange: ((Bool) -> Void)?
    var onToggle: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
}
