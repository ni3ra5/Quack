import os

/// Centralized logging. View live in Console.app or:
///   log stream --predicate 'subsystem == "com.quack.menubar"' --level debug
enum Log {
    static let calendar = Logger(subsystem: "com.quack.menubar", category: "calendar")
    static let reminders = Logger(subsystem: "com.quack.menubar", category: "reminders")
    static let brightness = Logger(subsystem: "com.quack.menubar", category: "brightness")
    static let swipe = Logger(subsystem: "com.quack.menubar", category: "swipe")
    static let permissions = Logger(subsystem: "com.quack.menubar", category: "permissions")
}
