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
/// (redacts Klipy API keys and JWT tokens). Entries older than 3 hours are purged.
final class HTTPRequestDebugStore: ObservableObject, @unchecked Sendable {
    static let shared = HTTPRequestDebugStore()

    @MainActor @Published private(set) var entries: [HTTPRequestDebugEntry] = []
    @MainActor private var nextSequenceNumber = 1
    @MainActor private var lastPurgeDate: Date?

    private let maxEntries: Int
    private let maxAge: TimeInterval = 3 * 60 * 60

    // MARK: - Init

    init(maxEntries: Int = 250) {
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
        if let lastPurge = lastPurgeDate, lastPurge > cutoff { return }
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

    /// Regex patterns for sanitizing URLs (Klipy API keys, JWT tokens).
    private static let urlSanitizers: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            ("(https?://api\\.klipy\\.com/api/v1/)[A-Za-z0-9]{50,}(/|$)", "$1[REDACTED]$2"),
            ("accessJwt=[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+", "accessJwt=[REDACTED]"),
            ("refreshJwt=[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+", "refreshJwt=[REDACTED]"),
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, template)
        }
    }()

    private static let jsonSanitizers: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            ("\"(accessJwt|refreshJwt|authorization)\"\\s*:\\s*\"[^\"]+\"", "\"$1\":\"[REDACTED]\""),
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, template)
        }
    }()

    /// Redact Klipy API keys and JWT tokens from a URL string.
    private static func sanitizeURL(_ url: String) -> String {
        var result = url
        let nsRange = NSRange(result.startIndex..., in: result)
        for (regex, template) in urlSanitizers {
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: template)
        }
        return result
    }

    /// Redact JWT tokens from a JSON error response body.
    static func sanitizeErrorResponseJSON(_ json: String?) -> String? {
        guard let json else { return nil }
        var result = json
        let nsRange = NSRange(result.startIndex..., in: result)
        for (regex, template) in jsonSanitizers {
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: template)
        }
        return result
    }
}
