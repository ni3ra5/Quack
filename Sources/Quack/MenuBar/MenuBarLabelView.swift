import SwiftUI
import QuackKit

/// The menu-bar title: the minimal duck, plus the countdown when enabled and a
/// (timed) meeting exists. Selection and formatting both use `env.now`, a
/// reliably-ticking clock, so the countdown can't go stale.
struct MenuBarLabelView: View {
    @ObservedObject var env: AppEnvironment

    var body: some View {
        HStack(spacing: 5) {
            DuckIconView()
            if env.settingsStore.settings.menuBarCountdownEnabled,
               let meeting = MeetingSelection.currentOrNext(from: env.meetingStore.upcoming, now: env.now),
               let title = CountdownFormatter.menuBarTitle(for: meeting, now: env.now) {
                Text(title)
            }
        }
    }
}
