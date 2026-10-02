import Foundation

// MARK: - ConstellationEndpoints

/// Every Constellation endpoint RULYX consumes, in one place.
///
/// Constellation (microcosm.blue) is a firehose-backed backlink index: it records
/// every reference between AT Protocol records, so "who blocks me" can be answered
/// from the `app.bsky.graph.block` records that point at an account, rather than
/// from a curated third-party database. RULYX uses it as the source for the
/// "Blocked by" list and for the list memberships behind "Listed on".
///
/// API contract (`blue.microcosm.links.getBacklinks`):
/// - `subject` — the DID (or AT URI) being linked to.
/// - `source` — `<collection>:<json.path.to.link>` of the *linking* records.
/// - `limit` — upper bound, not a page size: the server returns fewer records per
///   page than requested, so the cursor must be followed until it comes back empty.
/// - `cursor` — opaque, sequential. Pages cannot be requested in parallel.
///
/// - Note: Unlike a periodic snapshot service, the index needs no snapshot job of its
///   own and no registration — any DID can be queried read-only.
enum ConstellationEndpoints {
    static let baseURL = "https://constellation.microcosm.blue"

    /// Collection + JSON path of the link RULYX queries: the `subject` field of an
    /// `app.bsky.graph.block` record holds the DID of the account being blocked.
    static let blockSource = "app.bsky.graph.block:subject"

    /// Collection + JSON path of a list membership: the `subject` of an
    /// `app.bsky.graph.listitem` record is the listed profile.
    static let listItemSource = "app.bsky.graph.listitem:subject"

    /// The secondary link inside a listitem record — the list it belongs to.
    /// Used as `pathToOther` so the index groups memberships by list.
    static let listItemListPath = "list"

    /// Largest `limit` the Constellation API accepts.
    static let maxLimit = 100

    /// One page of backlinks pointing at `subject`.
    /// - Parameter limit: Requested page size; clamped to `1 ... maxLimit`.
    static func backlinks(
        subject: String,
        source: String = blockSource,
        limit: Int = maxLimit,
        cursor: String? = nil
    ) -> URL? {
        makeURL(
            endpoint: "blue.microcosm.links.getBacklinks",
            queryItems: [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "limit", value: String(clamped(limit))),
            ],
            cursor: cursor
        )
    }

    /// One page of "which of the secondary links point at `subject`" counts, grouped by
    /// the value of the secondary link. With `listItemSource` + `listItemListPath` the
    /// groups are the lists a profile appears on, so the number of entries is the
    /// "Listed on" count and each entry's `subject` is a list AT-URI.
    static func manyToManyCounts(
        subject: String,
        source: String = listItemSource,
        pathToOther: String = listItemListPath,
        limit: Int = maxLimit,
        cursor: String? = nil
    ) -> URL? {
        makeURL(
            endpoint: "blue.microcosm.links.getManyToManyCounts",
            queryItems: [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "pathToOther", value: pathToOther),
                URLQueryItem(name: "limit", value: String(clamped(limit))),
            ],
            cursor: cursor
        )
    }

    /// One page of the join records themselves (not just their counts), each carrying the
    /// linking record's repo and key. With the listitem source this yields the memberships
    /// — which list a profile is on, and the record key that dates it.
    static func manyToMany(
        subject: String,
        source: String = listItemSource,
        pathToOther: String = listItemListPath,
        limit: Int = maxLimit,
        cursor: String? = nil
    ) -> URL? {
        makeURL(
            endpoint: "blue.microcosm.links.getManyToMany",
            queryItems: [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "pathToOther", value: pathToOther),
                URLQueryItem(name: "limit", value: String(clamped(limit))),
            ],
            cursor: cursor
        )
    }

    /// `limit` is an upper bound, not a page size: the server returns fewer records per
    /// page than requested, so callers must follow the cursor until it is absent.
    private static func clamped(_ limit: Int) -> Int {
        min(max(limit, 1), maxLimit)
    }

    private static func makeURL(endpoint: String, queryItems: [URLQueryItem], cursor: String?) -> URL? {
        var components = URLComponents(string: "\(baseURL)/xrpc/\(endpoint)")
        var items = queryItems
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = items
        return components?.url
    }
}
