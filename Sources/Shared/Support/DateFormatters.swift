import Foundation

// MARK: - SharedDateFormatters

/// Shared date formatting utilities, including ISO 8601 parsing with and without fractional seconds.
/// Uses `ISO8601DateFormatter` (not `Date.ISO8601FormatStyle`) for reliability across Foundation versions.
enum SharedDateFormatters {
    /// Formatter for ISO 8601 dates with fractional seconds (e.g. "2024-01-15T10:30:00.000Z").
    private nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Formatter for ISO 8601 dates without fractional seconds (e.g. "2024-01-15T10:30:00Z").
    private nonisolated(unsafe) static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Formatter for UTC build timestamps (format: "yyyy-MM-dd HH:mm:ss").
    static let buildTimestampUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Parse an ISO 8601 string, trying fractional seconds first, then plain.
    /// Handles both "2024-01-15T10:30:00.000Z" and "2024-01-15T10:30:00Z" formats.
    static func parseISO8601(_ value: String) -> Date? {
        if let date = iso8601Fractional.date(from: value) {
            return date
        }
        return iso8601Plain.date(from: value)
    }
}
