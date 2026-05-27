import Foundation
import os

// MARK: - AppLogger

/// Thin wrapper around `os.Logger` with app-specific categories.
/// Usage: `AppLogger.search.info("...")`
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ajung.RULYX"

    /// Logger for search-related operations.
    static let search = Logger(subsystem: subsystem, category: "search")
    /// Logger for data persistence operations.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    /// Logger for moderation actions.
    static let moderation = Logger(subsystem: subsystem, category: "moderation")
    /// Logger for performance tracking.
    static let performance = Logger(subsystem: subsystem, category: "performance")
}
