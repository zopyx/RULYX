import Foundation

// MARK: - Constellation

/// Response from Constellation's `blue.microcosm.links.getBacklinks`.
struct ConstellationBacklinksResponse: Decodable {
    /// Total number of linking records for the subject — exact and independent of
    /// the requested page size, which makes it usable as a count in one request.
    let total: Int
    /// The records on this page.
    let records: [ConstellationBacklinkRecord]
    /// Opaque cursor for the next page; `nil` when the last page was reached.
    let cursor: String?
}

/// One record that links to the queried subject.
struct ConstellationBacklinkRecord: Decodable, Sendable {
    /// DID of the repository holding the linking record. For
    /// `app.bsky.graph.block` links this is the account that created the block.
    let did: String
    /// Collection of the linking record (`app.bsky.graph.block` here).
    let collection: String
    /// Record key of the linking record — a TID, so it carries the block's creation time.
    let rkey: String
}

/// A blocker derived from a Constellation backlink: the blocking account's DID plus
/// the block's creation date decoded from the record key.
///
/// Field names mirror `BlocklistEntry` on purpose — both sources feed the
/// same `BlueskyActor` conversion and the same on-disk cache path.
struct ConstellationBlockerEntry: Codable, Sendable {
    let did: String
    /// ISO 8601 date string of when the block was created.
    let blockedDate: String

    enum CodingKeys: String, CodingKey {
        case did
        case blockedDate = "blocked_date"
    }

    init(did: String, blockedDate: String) {
        self.did = did
        self.blockedDate = blockedDate
    }

    /// Builds an entry from a backlink record.
    /// A record whose key is not a decodable TID yields `nil`.
    init?(record: ConstellationBacklinkRecord) {
        guard let date = AtProtoTid.date(fromRecordKey: record.rkey) else { return nil }
        did = record.did
        blockedDate = SharedDateFormatters.formatISO8601(date)
    }
}

/// Cached Constellation blocker payload: the entries plus the index's own total.
///
/// The total is cached alongside the entries so a cached read reports the same
/// number as a fresh one — the dashboard count and the detail header are required
/// to agree regardless of which source answered.
struct ConstellationBlockerCache: Codable, Sendable {
    let total: Int
    let entries: [ConstellationBlockerEntry]
}

/// Response from Constellation's `blue.microcosm.links.getManyToManyCounts`.
///
/// One entry per value of the record's secondary link. Queried with the listitem source
/// and `pathToOther=list`, each entry is one list the profile appears on.
struct ConstellationManyToManyCountsResponse: Decodable {
    /// Groups keyed by the secondary link's value (here: a list AT-URI).
    let countsByOtherSubject: [ConstellationManyToManyCount]
    /// Opaque cursor for the next page; `nil` when the last page was reached.
    let cursor: String?

    enum CodingKeys: String, CodingKey {
        case countsByOtherSubject = "counts_by_other_subject"
        case cursor
    }
}

/// One group of the many-to-many count.
struct ConstellationManyToManyCount: Decodable, Sendable {
    /// The value of the secondary link — for list memberships, the list AT-URI.
    let subject: String
    /// Linking records in this group (a profile can be re-added to a list).
    let total: Int
    /// Distinct linking DIDs in this group.
    let distinct: Int
}

/// Cached "Listed on" payload: the list AT-URIs the profile appears on.
///
/// The URIs are kept (not just their number) so a later list detail view can reuse the
/// same walk instead of re-querying the index.
struct ConstellationListedOnCache: Codable, Sendable {
    let lists: [String]
}

/// Response from Constellation's `blue.microcosm.links.getManyToMany`.
///
/// Unlike `getManyToManyCounts` every item carries its linking record, so the membership
/// (not just its count) and the record key — a TID, therefore the date it was created —
/// are available.
struct ConstellationManyToManyResponse: Decodable {
    /// The join records on this page.
    let items: [ConstellationManyToManyItem]
    /// Opaque cursor for the next page; `nil` when the last page was reached.
    let cursor: String?

    struct ConstellationManyToManyItem: Decodable {
        /// The membership record (`app.bsky.graph.listitem`).
        let linkRecord: ConstellationLinkRecord
        /// The value of the secondary link — for list memberships, the list AT-URI.
        let otherSubject: String
    }

    /// Reference to a linking record by repo, collection and key.
    struct ConstellationLinkRecord: Decodable {
        let did: String
        let collection: String
        let rkey: String
    }
}

/// One list membership of a profile: which list, and the record key that dates it.
struct ConstellationListedOnMembership: Codable, Sendable, Hashable {
    /// AT-URI of the list the profile is on.
    let listURI: String
    /// Record key of the `app.bsky.graph.listitem` record (a TID carrying its timestamp).
    let recordKey: String
}

/// Cached membership walk: every list the profile appears on, with its membership record.
struct ConstellationListedOnMembershipCache: Codable, Sendable {
    let memberships: [ConstellationListedOnMembership]
}
