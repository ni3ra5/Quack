import Foundation

/// A coordinate-free snapshot of now-playing state — the scalar fields the panel
/// needs, decoupled from the vendored adapter's AppKit-bearing `TrackInfo` so the
/// display math stays pure and testable (mirrors ScreenGeometry vs WindowMover).
public struct NowPlayingSnapshot: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let isPlaying: Bool
    public let elapsedMicros: Double?
    public let timestampEpochMicros: Double?
    public let playbackRate: Double?

    public init(title: String?, artist: String?, isPlaying: Bool,
                elapsedMicros: Double?, timestampEpochMicros: Double?, playbackRate: Double?) {
        self.title = title; self.artist = artist; self.isPlaying = isPlaying
        self.elapsedMicros = elapsedMicros; self.timestampEpochMicros = timestampEpochMicros
        self.playbackRate = playbackRate
    }
}

public enum NowPlayingDisplay {
    /// Whether there is a real track to show (vs. the "Nothing playing" state).
    public static func hasTrack(_ s: NowPlayingSnapshot) -> Bool {
        !(s.title ?? "").isEmpty
    }

    /// Current elapsed seconds. When playing, interpolates from the last reported
    /// elapsed + rate * (now - reportTimestamp); when paused, the raw elapsed.
    /// Pure: caller supplies `nowEpochSeconds`. Mirrors the adapter's own
    /// `currentElapsedTime`, minus its `Date()` call, so it can be unit-tested.
    public static func elapsedSeconds(_ s: NowPlayingSnapshot, nowEpochSeconds: Double) -> Double? {
        guard let elapsedMicros = s.elapsedMicros else { return nil }
        let elapsed = elapsedMicros / 1_000_000
        guard s.isPlaying, let ts = s.timestampEpochMicros else { return elapsed }
        let rate = s.playbackRate ?? 0
        return elapsed + (nowEpochSeconds - ts) * rate
    }
}
