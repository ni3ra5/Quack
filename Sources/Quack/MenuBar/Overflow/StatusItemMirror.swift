import AppKit
import CoreGraphics
import QuackKit

/// Captures a live pixel snapshot of a single status-item window, so the reveal
/// panel shows exactly what the notch is hiding (real battery %, Wi-Fi state,
/// etc.) rather than a generic app icon. Requires Screen Recording permission;
/// returns nil without it, and the caller then omits that item.
enum StatusItemMirror {

    /// A snapshot of just this status item's window. `CGWindowListCreateImage`
    /// is deprecated on macOS 14 in favour of ScreenCaptureKit, but remains
    /// functional through current macOS and is far simpler for a single tiny
    /// capture; ScreenCaptureKit migration is deferred. Returns nil if Screen
    /// Recording is not granted (the call yields nil in that case on 14+).
    static func snapshot(of item: StatusItemFrame) -> NSImage? {
        let cgImage = CGWindowListCreateImage(
            .null,                                   // use the window's own bounds
            .optionIncludingWindow,
            item.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: item.frame.size)
    }
}
