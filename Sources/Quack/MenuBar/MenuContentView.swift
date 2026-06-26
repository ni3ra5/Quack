import SwiftUI
import AppKit
import QuackKit

/// The dropdown (window-style popover) shown when the menu-bar item is clicked.
/// Styled after a calendar menu: upcoming meetings grouped by day with colored
/// dots, then Settings and Quit. All-day events appear in the list.
struct MenuContentView: View {
    @EnvironmentObject var env: AppEnvironment

    // Use the environment's reliably-ticking clock for relative headers.
    private var now: Date { env.now }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 300)
        .onAppear { env.refreshCalendarNow() }
    }

    @ViewBuilder
    private var content: some View {
        if !env.settingsStore.settings.calendarEnabled {
            placeholder("Calendar is off")
        } else if env.permissions.status(for: .calendar) != .granted {
            placeholder("Calendar access needed — open Settings")
        } else {
            let sections = MeetingGrouping.byDay(env.meetingStore.upcoming, now: now)
            if sections.isEmpty {
                placeholder("No upcoming meetings")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            Text(header(for: section))
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10).padding(.bottom, 2)
                            ForEach(section.events) { event in
                                MeetingRow(event: event)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRowButton(title: "Settings…", shortcut: ",") { env.showSettings() }
            MenuRowButton(title: "Quit Quack", shortcut: "Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 14)
    }

    private func header(for section: DaySection) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(section.dayStart) {
            if let next = section.events.first(where: { !$0.isAllDay && $0.start > now }) {
                return "Upcoming in \(CountdownFormatter.relative(next.start.timeIntervalSince(now)))"
            }
            return "Today"
        }
        if cal.isDateInTomorrow(section.dayStart) { return "Tomorrow" }
        return Self.dayFormatter.string(from: section.dayStart)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()
}

/// One meeting row: colored calendar bar, time (or "All day"), title.
/// Clicking a row with a join link opens it.
private struct MeetingRow: View {
    @EnvironmentObject var env: AppEnvironment
    let event: MeetingEvent
    @State private var hovering = false

    private var joinURL: URL? { MeetingURLParser.joinURL(for: event) }

    var body: some View {
        Button { if let joinURL { NSWorkspace.shared.open(joinURL) } } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: event.calendarColorHex) ?? .accentColor)
                    .frame(width: 3, height: 16)
                Text(timeText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: event.isAllDay ? 0 : 58, alignment: .leading)
                Text(event.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if joinURL != nil {
                    Spacer(minLength: 4)
                    Image(systemName: "video.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .instantHover($hovering)
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        return Self.time.string(from: event.start)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
}

/// A footer menu item styled to match the list rows, with hover highlight and a
/// right-aligned keyboard-shortcut hint.
struct MenuRowButton: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text("⌘\(shortcut)").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .instantHover($hovering)
    }
}

