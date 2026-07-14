import Foundation

// MARK: - Record Creation

/// Request body for creating a list item record with explicit collection and record fields.
struct CreateRecordRequest: Encodable {
    let repo: String
    let collection: String
    let record: ListItemRecord
}

/// Generic request body for creating a record in a specified collection.
/// Used for posts, likes, reposts, follows, blocks, and thread/post gates.
struct CreateGenericRecordRequest<Record: Encodable>: Encodable {
    let repo: String
    let collection: String
    let record: Record
    /// Optional rkey for record creation at a specific key (e.g., threadgate uses the post's rkey).
    let rkey: String?

    init(repo: String, collection: String, record: Record, rkey: String? = nil) {
        self.repo = repo
        self.collection = collection
        self.record = record
        self.rkey = rkey
    }

    enum CodingKeys: String, CodingKey {
        case repo
        case collection
        case record
        case rkey
    }
}

/// Request body for updating a record via `com.atproto.repo.putRecord`.
struct PutRecordRequest<Record: Encodable>: Encodable {
    let repo: String
    let collection: String
    let rkey: String
    let record: Record
}

/// The record value for a list item (member) in a list.
struct ListItemRecord: Encodable {
    let createdAt: String
    let list: String
    let subject: String

    enum CodingKeys: String, CodingKey {
        case createdAt
        case list
        case subject
    }
}

/// The record value for a list definition (`app.bsky.graph.list`).
struct ListRecord: Encodable {
    let type: String
    let purpose: String
    let name: String
    let description: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case purpose
        case name
        case description
        case createdAt
    }
}

/// Generic record for a follow or block relationship (subject-based, no list).
struct SubjectRecord: Encodable {
    let type: String
    let subject: String
    let createdAt: String

    init(type: String, subject: String, createdAt: String = ISO8601DateFormatter().string(from: .now)) {
        self.type = type
        self.subject = subject
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subject
        case createdAt
    }
}

/// Request body for muting/unmuting an actor by DID.
struct ActorReferenceRequest: Encodable {
    let actor: String
}

/// Request body for muting/unmuting an actor list.
struct ListReferenceRequest: Codable {
    let list: String
}

/// Response from `com.atproto.repo.createRecord`.
struct CreateRecordResponse: Decodable {
    let uri: String
    let cid: String
}

/// Response from querying records in a collection.
struct ListRecordsResponse: Decodable {
    let cursor: String?
    let records: [ListRecordEntry]
}

/// A single record entry from `com.atproto.repo.listRecords`.
struct ListRecordEntry: Decodable {
    let uri: String
    let cid: String
    let value: ListItemRecordValue
}

struct ListItemRecordValue: Decodable {
    let createdAt: String
    let list: String
    let subject: String
}

/// A single record entry from `com.atproto.repo.listRecords` for block records.
struct BlockListRecordEntry: Decodable {
    let uri: String
    let cid: String
    let value: BlockRecordValue
}

/// The value of an `app.bsky.graph.block` record.
struct BlockRecordValue: Decodable {
    let subject: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case subject
        case createdAt
    }
}

/// Response from listing `app.bsky.graph.block` records.
struct BlockListRecordsResponse: Decodable {
    let cursor: String?
    let records: [BlockListRecordEntry]
}

/// Request body for `com.atproto.repo.deleteRecord`.
struct DeleteRecordRequest: Encodable {
    let repo: String
    let collection: String
    let rkey: String
}

/// Placeholder for API calls that return no meaningful body (HTTP 200 with `{}`).
struct EmptyResponse: Decodable {}

// MARK: - AT URI Parsing

/// Parsed components of an AT URI (`at://{repo}/{collection}/{rkey}`).
struct ATURIComponents {
    let repo: String
    let collection: String
    let rkey: String
}

/// Parses an AT URI string into its components.
/// Throws `BlueskyAPIError.invalidResponse` if the URI does not match the expected format.
func parseATURI(_ uri: String) throws -> ATURIComponents {
    guard uri.hasPrefix("at://") else {
        throw BlueskyAPIError.invalidResponse
    }

    let value = String(uri.dropFirst(5))
    let segments = value.split(separator: "/")
    guard segments.count >= 3 else {
        throw BlueskyAPIError.invalidResponse
    }

    return ATURIComponents(
        repo: String(segments[0]),
        collection: String(segments[1]),
        rkey: String(segments[2])
    )
}

/// Parses an optional ISO 8601 date string into a `Date`.
func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return SharedDateFormatters.parseISO8601(value)
}

/// Returns a human-readable relative time string (e.g., "3m ago", "2h ago", "5d ago") or
/// an abbreviated absolute date for items 28+ days old.
@MainActor
func relativeTimeString(from date: Date) -> String {
    let interval = -date.timeIntervalSinceNow
    let minutes = Int(interval / 60)
    let hours = minutes / 60
    let days = hours / 24

    if minutes < 1 {
        return String.localized("time.just_now")
    }
    if minutes < 60 {
        let key = minutes == 1 ? "time.minute_ago" : "time.minutes_ago"
        return loc(key).replacingOccurrences(of: "{n}", with: "\(minutes)")
    }
    if hours < 24 {
        let key = hours == 1 ? "time.hour_ago" : "time.hours_ago"
        return loc(key).replacingOccurrences(of: "{n}", with: "\(hours)")
    }
    if days < 28 {
        let key = days == 1 ? "time.day_ago" : "time.days_ago"
        return loc(key).replacingOccurrences(of: "{n}", with: "\(days)")
    }

    return date.formatted(date: .abbreviated, time: .omitted)
}

/// Maps the API's `ProfileViewerState` to the app's domain model `BlueskyViewerState`.
func mapViewerState(_ viewer: ProfileViewerState?) -> BlueskyViewerState? {
    guard let viewer else { return nil }

    return BlueskyViewerState(
        muted: viewer.muted ?? false,
        blockedBy: viewer.blockedBy ?? false,
        isBlocking: viewer.blocking != nil,
        blockingRecordURI: viewer.blocking,
        isFollowing: viewer.following != nil,
        followingRecordURI: viewer.following,
        followsYou: viewer.followedBy != nil,
        mutedByListName: viewer.mutedByList?.name,
        blockingByListName: [viewer.blockingByList?.name].compactMap(\.self)
    )
}
