import AppKit

/// Plays the bundled "quack" when a meeting starts.
@MainActor
final class QuackSound {
    private var sound: NSSound?

    func play() {
        if sound == nil, let url = Bundle.main.url(forResource: "quack", withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: true)
        }
        sound?.stop()
        sound?.play()
    }
}
