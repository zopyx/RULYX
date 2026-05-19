import Foundation

enum HTTPRequestDebugState: String {
    case running
    case succeeded
    case failed
}

struct HTTPRequestDebugEntry: Identifiable {
    let id: UUID
    let sequenceNumber: Int
    let source: String?
    let origin: String?
    let method: String
    let url: String
    let startedAt: Date
    var state: HTTPRequestDebugState
    var duration: TimeInterval?
    var statusCode: Int?
    var errorMessage: String?
    var errorResponseJSON: String?
}

final class HTTPRequestDebugStore: ObservableObject, @unchecked Sendable {
    static let shared = HTTPRequestDebugStore()

    @MainActor @Published private(set) var entries: [HTTPRequestDebugEntry] = []
    @MainActor private var nextSequenceNumber = 1

    private let maxEntries: Int

    init(maxEntries: Int = 250) {
        self.maxEntries = maxEntries
    }

    func begin(request: URLRequest, source: String? = nil, origin: String? = nil) async -> UUID {
        let entryID = UUID()
        let startedAt = Date()
        let sanitizedURL = Self.sanitizeURL(request.url?.absoluteString ?? "about:blank")
        await MainActor.run {
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

    func succeed(id: UUID, statusCode: Int) async {
        await MainActor.run {
            update(id: id) { entry in
                entry.state = .succeeded
                entry.statusCode = statusCode
                entry.duration = Date().timeIntervalSince(entry.startedAt)
                entry.errorMessage = nil
                entry.errorResponseJSON = nil
            }
        }
    }

    func fail(id: UUID, statusCode: Int? = nil, errorMessage: String?, errorResponseJSON: String? = nil) async {
        let sanitizedJSON = Self.sanitizeErrorResponseJSON(errorResponseJSON)
        await MainActor.run {
            update(id: id) { entry in
                entry.state = .failed
                entry.statusCode = statusCode
                entry.duration = Date().timeIntervalSince(entry.startedAt)
                entry.errorMessage = errorMessage
                entry.errorResponseJSON = sanitizedJSON
            }
        }
    }

    func clear() async {
        await MainActor.run {
            entries.removeAll()
            nextSequenceNumber = 1
        }
    }

    @MainActor
    private func update(id: UUID, mutate: (inout HTTPRequestDebugEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        mutate(&entry)
        entries[index] = entry
    }

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

    private static func sanitizeURL(_ url: String) -> String {
        var result = url
        let nsRange = NSRange(result.startIndex..., in: result)
        for (regex, template) in urlSanitizers {
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: template)
        }
        return result
    }

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
