import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ajung.BlueskyModeration"

    static let search = Logger(subsystem: subsystem, category: "search")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let moderation = Logger(subsystem: subsystem, category: "moderation")
    static let performance = Logger(subsystem: subsystem, category: "performance")
}
