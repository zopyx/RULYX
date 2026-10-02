import Foundation

// MARK: - BlueskyListMember

/// Represents a single actor who is a member of a Bluesky list.
/// Tracks the membership record URI, the associated actor profile,
/// and viewer-specific relationship state (follows/followed-by).
struct BlueskyListMember: Identifiable, Hashable, Sendable {
    // MARK: - Properties

    /// The AT URI of the list membership record (also used as the unique identifier).
    let id: String
    /// The AT record URI that represents this member's inclusion in the list.
    let recordURI: String
    /// The Bluesky actor profile for this member.
    let actor: BlueskyActor
    /// The timestamp when this member was added to the list.
    /// Prefer the list item record's `createdAt` value returned by the API.
    /// Falls back to the list item record key timestamp when the API omits `createdAt`.
    let createdAt: Date?
    /// Viewer-specific relationship state: whether the current user follows this
    /// member, is followed by them, blocks them, etc. Populated from the API
    /// response when available; nil when the relationship is unknown.
    /// Mutable to allow optimistic UI updates (follow/unfollow via double-tap).
    var viewerState: BlueskyViewerState?

    // MARK: - Init

    /// Creates a list member entry.
    /// - Parameters:
    ///   - recordURI: The AT URI of the list membership record.
    ///   - actor: The Bluesky actor profile for this member.
    ///   - createdAt: The date the member was added to the list, when provided by the API.
    ///   - viewerState: Viewer relationship state for this member.
    init(recordURI: String, actor: BlueskyActor, createdAt: Date? = nil, viewerState: BlueskyViewerState? = nil) {
        id = recordURI
        self.recordURI = recordURI
        self.actor = actor
        self.createdAt = createdAt ?? AtProtoTid.date(fromATURI: recordURI)
        self.viewerState = viewerState
    }
}
