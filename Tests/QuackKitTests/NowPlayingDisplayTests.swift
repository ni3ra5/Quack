import Testing
@testable import QuackKit

@Suite struct NowPlayingDisplayTests {
    private func snap(title: String? = "T", playing: Bool = true,
                      elapsed: Double? = nil, ts: Double? = nil, rate: Double? = nil) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: title, artist: "A", isPlaying: playing,
                           elapsedMicros: elapsed, timestampEpochMicros: ts, playbackRate: rate)
    }

    @Test func hasTrackWhenTitlePresent() {
        #expect(NowPlayingDisplay.hasTrack(snap(title: "Song")))
        #expect(!NowPlayingDisplay.hasTrack(snap(title: nil)))
        #expect(!NowPlayingDisplay.hasTrack(snap(title: "")))
    }

    @Test func elapsedNilWhenNoTiming() {
        #expect(NowPlayingDisplay.elapsedSeconds(snap(), nowEpochSeconds: 1000) == nil)
    }

    @Test func elapsedIsRawWhenPaused() {
        // paused: elapsed = elapsedMicros/1e6, no interpolation
        let s = snap(playing: false, elapsed: 30_000_000, ts: 900, rate: 1)
        #expect(NowPlayingDisplay.elapsedSeconds(s, nowEpochSeconds: 1000) == 30)
    }

    @Test func elapsedInterpolatesWhenPlaying() {
        // playing: 30s at ts=900, rate 1, now=1000 → 30 + (1000-900)*1 = 130
        let s = snap(playing: true, elapsed: 30_000_000, ts: 900, rate: 1)
        #expect(NowPlayingDisplay.elapsedSeconds(s, nowEpochSeconds: 1000) == 130)
    }

    @Test func elapsedUsesRateWhenPlaying() {
        // rate 0 → no advance
        let s = snap(playing: true, elapsed: 30_000_000, ts: 900, rate: 0)
        #expect(NowPlayingDisplay.elapsedSeconds(s, nowEpochSeconds: 1000) == 30)
    }
}
