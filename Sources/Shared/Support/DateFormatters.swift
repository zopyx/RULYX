import Foundation

enum SharedDateFormatters {
    private static let iso8601FractionalStrategy = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso8601PlainStrategy = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static let buildTimestampUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func parseISO8601(_ value: String) -> Date? {
        if let date = try? iso8601FractionalStrategy.parse(value) { return date }
        return try? iso8601PlainStrategy.parse(value)
    }
}
