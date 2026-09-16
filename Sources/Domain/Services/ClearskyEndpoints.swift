import Foundation

// MARK: - ClearskyEndpoints

/// Every ClearSky endpoint RULYX consumes, in one place.
///
/// ClearSky is a third-party service whose availability is outside our control
/// (observed: multi-hour 5xx outages on 2026-09-12 … 2026-09-16). All ClearSky
/// traffic is built from the URLs below, so swapping the block/blocker data
/// provider is a change confined to this file plus a new
/// `BlueskyClearSkyServicing` implementation — never a change in feature code.
///
/// Provider-swap checklist:
/// 1. Repoint the builders below at the new provider.
/// 2. Implement `BlueskyClearSkyServicing` against it (`Sources/Domain/Services/Protocols/`).
/// 3. Keep handle → DID resolution out of it: `LiveBlueskyClient` resolves via the
///    AT Protocol (`com.atproto.identity.resolveHandle`) and only falls back here.
///
/// - Note: GraphTracks (graphtracks.com) cannot replace ClearSky today — its
///   developer API (OpenAPI 0.1.0) exposes analytics only, with no blocklist,
///   blocked-by, moderation-list or handle-resolution endpoints.
enum ClearskyEndpoints {
    /// Blocklist host: `blocklist`, `single-blocklist`, `get-did`.
    static let blocklistBaseURL = "https://public.api.clearsky.services/api/v1/anon"
    /// Moderation-list host: `get-list`, `get-list/total`.
    static let listsBaseURL = "https://api.clearsky.app/csky/api/v1"

    /// DID used purely as a liveness probe. Syntactically valid, no known account,
    /// so a healthy ClearSky answers `404` with a tiny body instead of paginating
    /// a real blocklist.
    static let healthProbeDID = "did:plc:aaaaaaaaaaaaaaaaaaaaaaaa"

    /// Liveness probe for the ClearSky API (see `ClearskyHeartbeatService`).
    static var healthProbeURL: URL? {
        blocklist(endpoint: "blocklist", actorDID: healthProbeDID, page: 1)
    }

    /// One page of a blocklist endpoint (`blocklist` = accounts we block,
    /// `single-blocklist` = accounts blocking us). Page 1 has no page suffix.
    static func blocklist(endpoint: String, actorDID: String, page: Int) -> URL? {
        let suffix = page == 1 ? "" : "/\(page)"
        return URL(string: "\(blocklistBaseURL)/\(endpoint)/\(actorDID)\(suffix)")
    }

    /// Handle → DID via ClearSky. Fallback only — prefer the AT Protocol resolver.
    static func did(forHandle handle: String) -> URL? {
        guard let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(blocklistBaseURL)/get-did/\(encoded)")
    }

    /// One page of the moderation-list endpoint. Page 1 has no page suffix.
    static func lists(forHandle handle: String, page: Int) -> URL? {
        let suffix = page == 1 ? "" : "/\(page)"
        guard let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(listsBaseURL)/get-list/\(encoded)\(suffix)")
    }

    /// Total number of moderation lists a handle appears on (fast counter endpoint).
    static func listsTotal(forHandle handle: String) -> URL? {
        guard let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(listsBaseURL)/get-list/total/\(encoded)")
    }
}
