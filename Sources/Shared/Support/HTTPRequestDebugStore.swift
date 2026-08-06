import Foundation

// MARK: - HTTPRequestDebugState

/// The state of a tracked HTTP request.
enum HTTPRequestDebugState: String {
    /// Request is in-flight.
    case running
    /// Request completed successfully.
    case succeeded
    /// Request failed.
    case failed
}

// MARK: - HTTPRequestDebugEntry

/// A single entry in the HTTP debug log.
struct HTTPRequestDebugEntry: Identifiable {
    let id: UUID
    /// Monotonically increasing sequence number for ordering.
    let sequenceNumber: Int
    /// Description of where the request originated (e.g. "BlueskyProfileService").
    let source: String?
    /// Origin label for grouping related requests.
    let origin: String?
    /// HTTP method used.
    let method: String
    /// Redacted URL (API keys and tokens are sanitized).
    let url: String
    /// When the request started.
    let startedAt: Date
    /// Current state of the request.
    var state: HTTPRequestDebugState
    /// Duration of the request once completed.
    var duration: TimeInterval?
    /// HTTP response status code.
    var statusCode: Int?
    /// Error message if the request failed.
    var errorMessage: String?
    /// Redacted JSON error response body.
    var errorResponseJSON: String?
}

// MARK: - HTTPRequestDebugStore

/// In-memory store of HTTP request debug entries, with automatic URL sanitization
/// (redacts Klipy API keys and JWT tokens). Entries older than 24 hours are purged
/// (see `maxAge`). `maxEntries` (2000) caps memory regardless of age.
/// @unchecked Sendable: ObservableObject with @MainActor-isolated mutable state via @Published.
final class HTTPRequestDebugStore: ObservableObject, @unchecked Sendable {
    static let shared = HTTPRequestDebugStore()

    @MainActor @Published private(set) var entries: [HTTPRequestDebugEntry] = []
    @MainActor private var nextSequenceNumber = 1
    @MainActor private var lastPurgeDate: Date?
    /// Per-endpoint latency tracking for the performance overlay.
    @MainActor private var endpointStats: [String: EndpointLatencyStats] = [:]

    private let maxEntries: Int
    private let maxAge: TimeInterval = 24 * 60 * 60

    // MARK: - Init

    init(maxEntries: Int = 2000) {
        self.maxEntries = maxEntries
    }

    // MARK: - Public

    /// Register a new request and return its tracking ID.
    func begin(request: URLRequest, source: String? = nil, origin: String? = nil) async -> UUID {
        let entryID = UUID()
        let startedAt = Date()
        let sanitizedURL = Self.sanitizeURL(request.url?.absoluteString ?? "about:blank")
        await MainActor.run {
            purgeOldEntries()
            let entry = HTTPRequestDebugEntry(
                id: entryID,
                sequenceNumber: nextSequenceNumber,
                source: source,
                origin: origin,
                method: request.httpMethod ?? "GET",
                url: sanitizedURL,
                startedAt: startedAt,
                state: .running,
                duration: nil,
                statusCode: nil,
                errorMessage: nil,
                errorResponseJSON: nil
            )
            nextSequenceNumber += 1
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries.removeLast(entries.count - maxEntries)
            }
        }
        return entryID
    }

    /// Mark a request as successful with the HTTP status code.
    func succeed(id: UUID, statusCode: Int) async {
        await MainActor.run {
            purgeOldEntries()
            update(id: id) { entry in
                entry.state = .succeeded
                entry.statusCode = statusCode
                entry.duration = Date().timeIntervalSince(entry.startedAt)
                entry.errorMessage = nil
                entry.errorResponseJSON = nil
            }
        }
    }

    /// Mark a request as failed with optional status code and error details.
    func fail(id: UUID, statusCode: Int? = nil, errorMessage: String?, errorResponseJSON: String? = nil) async {
        let sanitizedJSON = Self.sanitizeErrorResponseJSON(errorResponseJSON)
        await MainActor.run {
            purgeOldEntries()
            update(id: id) { entry in
                entry.state = .failed
                entry.statusCode = statusCode
                entry.duration = Date().timeIntervalSince(entry.startedAt)
                entry.errorMessage = errorMessage
                entry.errorResponseJSON = sanitizedJSON
            }
        }
    }

    /// Clear all entries and reset the sequence counter.
    func clear() async {
        await MainActor.run {
            entries.removeAll()
            nextSequenceNumber = 1
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private func purgeOldEntries() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        if let lastPurge = lastPurgeDate, lastPurge > cutoff {
            return
        }
        lastPurgeDate = Date()
        entries.removeAll { $0.startedAt < cutoff }
    }

    @MainActor
    private func update(id: UUID, mutate: (inout HTTPRequestDebugEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        mutate(&entry)
        entries[index] = entry
    }

    // MARK: - URL Sanitization

    /// Regex patterns for sanitizing URLs (Klipy API keys, JWT tokens, Bearer tokens).
    private static let urlSanitizers: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            ("(https?://api\\.klipy\\.com/api/v1/)[A-Za-z0-9]{50,}(/|$)", "$1[REDACTED]$2"),
            ("accessJwt=[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+", "accessJwt=[REDACTED]"),
            ("refreshJwt=[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+", "refreshJwt=[REDACTED]"),
            ("Bearer [A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+", "Bearer [REDACTED]"),
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, template)
        }
    }()

    private static let jsonSanitizers: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            ("\"(accessJwt|refreshJwt|authorization)\"\\s*:\\s*\"[^\"]+\"", "\"$1\":\"[REDACTED]\""),
            ("Bearer [A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+", "Bearer [REDACTED]"),
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, template)
        }
    }()

    /// Redact Klipy API keys and JWT tokens from a URL string.
    private static func sanitizeURL(_ url: String) -> String {
        var result = url
        for (regex, template) in urlSanitizers {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: template)
        }
        return result
    }

    /// Redact JWT tokens from a JSON error response body.
    static func sanitizeErrorResponseJSON(_ json: String?) -> String? {
        guard let json else { return nil }
        var result = json
        for (regex, template) in jsonSanitizers {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: template)
        }
        return result
    }
}

// MARK: - Stats models

/// Per-endpoint latency tracking for the performance monitor overlay.
struct EndpointLatencyStats: Codable {
    /// The endpoint path (e.g. "app.bsky.actor.getProfile").
    let endpoint: String
    /// Total request count.
    let count: Int
    /// Total duration of all requests in seconds.
    let totalDuration: TimeInterval
    /// Maximum duration observed.
    let maxDuration: TimeInterval
    /// Minimum duration observed.
    let minDuration: TimeInterval

    var averageDuration: TimeInterval {
        count > 0 ? totalDuration / Double(count) : 0
    }
}

/// Snapshot of performance metrics at a point in time.
struct PerformanceMetricsSnapshot: Codable {
    /// Total requests in the current session.
    let totalRequests: Int
    /// Session-level average latency.
    let averageLatency: TimeInterval
    /// Per-endpoint stats.
    let endpoints: [EndpointLatencyStats]
    /// Cache hit count.
    let cacheHits: Int
    /// Cache miss count.
    let cacheMisses: Int
    /// Cache hit ratio.
    let cacheHitRatio: Double
    /// Timestamp of the snapshot.
    let timestamp: Date
}

/// Aggregation granularity for the stats timeline chart.
enum HTTPDebugStatsGranularity: String, CaseIterable, Identifiable {
    case day
    case hour
    case minute
    case fiveMinutes

    var id: String {
        rawValue
    }

    var bucketInterval: TimeInterval {
        switch self {
        case .day: 86400
        case .hour: 3600
        case .minute: 60
        case .fiveMinutes: 300
        }
    }

    var localizationKey: String {
        switch self {
        case .day: "debug.http.stats.granularity.day"
        case .hour: "debug.http.stats.granularity.hour"
        case .minute: "debug.http.stats.granularity.minute"
        case .fiveMinutes: "debug.http.stats.granularity.5min"
        }
    }
}

/// A single time bucket for HTTP request stats.
struct HTTPDebugStatsBucket: Identifiable {
    let id = UUID()
    /// Start of the 5-minute slot.
    let slotStart: Date
    /// Total requests in this bucket.
    let total: Int
    /// Requests that succeeded.
    let succeeded: Int
    /// Requests that failed.
    let failed: Int
    /// Requests still in-flight at render time.
    let running: Int
    /// Average response duration in seconds (completed requests only).
    let avgDuration: TimeInterval
}

/// Aggregated stats for a single source (component) over the 24h window.
struct HTTPDebugSourceStats: Identifiable {
    let id = UUID()
    let source: String
    let total: Int
    let succeeded: Int
    let failed: Int
    let avgDuration: TimeInterval
}

// MARK: - Stats & export extensions

extension HTTPRequestDebugStore {
    /// Time buckets at the given granularity over the 24-hour window.
    @MainActor
    func statsBuckets(granularity: HTTPDebugStatsGranularity) -> [HTTPDebugStatsBucket] {
        buildBuckets(granularity: granularity)
    }

    /// Aggregated stats grouped by source, sorted by total descending.
    @MainActor
    var sourceStats: [HTTPDebugSourceStats] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let recent = entries.filter { $0.startedAt >= cutoff }
        let grouped = Dictionary(grouping: recent, by: { $0.source ?? "unknown" })
        return grouped.map { source, group in
            let completed = group.filter { $0.state != .running }
            return HTTPDebugSourceStats(
                source: source,
                total: group.count,
                succeeded: group.filter { $0.state == .succeeded }.count,
                failed: group.filter { $0.state == .failed }.count,
                avgDuration: completed.isEmpty ? 0 : completed.compactMap(\.duration).reduce(0, +) / Double(completed.count)
            )
        }.sorted { $0.total > $1.total }
    }

    @MainActor
    private func buildBuckets(granularity: HTTPDebugStatsGranularity) -> [HTTPDebugStatsBucket] {
        let now = Date()
        let calendar = Calendar.current
        let interval = granularity.bucketInterval

        // Floor now to the bucket boundary.
        let floorNow = floorToInterval(now, interval: interval, calendar: calendar)
        var buckets: [HTTPDebugStatsBucket] = []

        let maxSlots = Int(maxAge / interval)
        buckets.reserveCapacity(maxSlots)

        var slot = floorNow.addingTimeInterval(-maxAge + interval)
        while slot <= floorNow {
            let slotEnd = slot.addingTimeInterval(interval)
            let slotEntries = entries.filter { $0.startedAt >= slot && $0.startedAt < slotEnd }
            let completed = slotEntries.filter { $0.state != .running }
            buckets.append(HTTPDebugStatsBucket(
                slotStart: slot,
                total: slotEntries.count,
                succeeded: slotEntries.filter { $0.state == .succeeded }.count,
                failed: slotEntries.filter { $0.state == .failed }.count,
                running: slotEntries.filter { $0.state == .running }.count,
                avgDuration: completed.isEmpty ? 0 : completed.compactMap(\.duration).reduce(0, +) / Double(completed.count)
            ))
            slot = slotEnd
        }
        return buckets
    }

    private func floorToInterval(_ date: Date, interval: TimeInterval, calendar: Calendar) -> Date {
        if interval >= 86400 {
            // Day granularity: floor to start of day
            return calendar.startOfDay(for: date)
        } else if interval >= 3600 {
            // Hour granularity: floor to start of hour
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: comps) ?? date
        } else if interval >= 60 {
            // Minute granularity: floor to minute boundary
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return calendar.date(from: comps) ?? date
        } else {
            // Sub-minute: floor to interval boundary
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let totalSeconds = TimeInterval(comps.second ?? 0) + TimeInterval(comps.nanosecond ?? 0) / 1_000_000_000
            let flooredSeconds = floor(totalSeconds / interval) * interval
            return calendar.date(bySetting: .second, value: Int(flooredSeconds), of: date) ?? date
        }
    }

    // MARK: - CSV

    /// A full CSV string of all tracked entries (row-level).
    @MainActor
    var csvString: String {
        let header = "Time Slot,Source,Origin,Method,URL,Status Code,State,Duration (ms)"
        let iso = ISO8601DateFormatter()
        let rows = entries.map { entry -> String in
            let time = iso.string(from: entry.startedAt)
            let source = escapeCSV(entry.source ?? "")
            let origin = escapeCSV(entry.origin ?? "")
            let method = entry.method
            let url = escapeCSV(entry.url)
            let code = entry.statusCode.map(String.init) ?? ""
            let state = entry.state.rawValue
            let dur = entry.duration.map { String(Int($0 * 1000)) } ?? ""
            return "\(time),\(source),\(origin),\(method),\(url),\(code),\(state),\(dur)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Aggregated CSV by time bucket at the given granularity.
    @MainActor
    var csvBucketsString: String {
        csvBucketsString(granularity: .fiveMinutes)
    }

    /// Aggregated CSV by time bucket at the specified granularity.
    @MainActor
    func csvBucketsString(granularity: HTTPDebugStatsGranularity) -> String {
        let header = "Time Slot,Total,Succeeded,Failed,Running,Avg Duration (ms)"
        let iso = ISO8601DateFormatter()
        let rows = statsBuckets(granularity: granularity).map { bucket -> String in
            let time = iso.string(from: bucket.slotStart)
            return "\(time),\(bucket.total),\(bucket.succeeded),\(bucket.failed),\(bucket.running),\(Int(bucket.avgDuration * 1000))"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Aggregated CSV by source.
    @MainActor
    var csvSourceString: String {
        let header = "Source,Total,Succeeded,Failed,Avg Duration (ms)"
        let rows = sourceStats.map { stat -> String in
            let src = escapeCSV(stat.source)
            return "\(src),\(stat.total),\(stat.succeeded),\(stat.failed),\(Int(stat.avgDuration * 1000))"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Writes a CSV file to a temporary directory and returns its URL for sharing.
    @MainActor
    func writeExportCSV(fileName: String = "http_debug_export.csv") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? csvString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
