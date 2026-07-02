import Foundation
import Combine
import MediaRemoteAdapter

/// Wraps the vendored MediaController. Publishes the current track and forwards
/// transport commands. Fail-soft: if the adapter never emits or dies, `track`
/// simply stays nil and the panel shows "Nothing playing" — no crash. Spawns
/// perl via Process/pipes only; installs no event tap (CLAUDE.md freeze rules
/// do not apply). Not App-Store/sandbox compatible (perl + private framework).
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: TrackInfo?

    private let controller = MediaController()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        controller.onTrackInfoReceived = { [weak self] info in
            // Adapter already hops to main for this callback.
            self?.track = info
        }
        controller.onListenerTerminated = { [weak self] in
            // Listener died; degrade to nothing rather than stale data.
            self?.track = nil
        }
        controller.startListening()
    }

    func stop() {
        guard started else { return }
        started = false
        controller.stopListening()
        controller.onTrackInfoReceived = nil
        controller.onListenerTerminated = nil
        track = nil
    }

    func togglePlayPause() { controller.togglePlayPause() }
    func next() { controller.nextTrack() }
    func previous() { controller.previousTrack() }
}
