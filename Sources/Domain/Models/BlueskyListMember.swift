import Foundation

/// Represents a single actor who is a member of a Bluesky list.
/// Tracks the membership record URI and the associated actor profile.
struct BlueskyListMember: Identifiable, Hashable {
    // MARK: - Properties

    /// The AT URI of the list membership record (also used as the unique identifier).
    let id: String
    /// The AT record URI that represents this member's inclusion in the list.
    let recordURI: String
    /// The Bluesky actor profile for this member.
    let actor: BlueskyActor
    /// The timestamp when this member was added to the list.
    /// Extracted from the record URI's timestamp ID (TID) when not explicitly provided.
    let createdAt: Date?

    // MARK: - Init

    /// Creates a list member entry.
    /// - Parameters:
    ///   - recordURI: The AT URI of the list membership record.
    ///   - actor: The Bluesky actor profile for this member.
    ///   - createdAt: The date the member was added. If nil, extracted from the URI's TID.
    init(recordURI: String, actor: BlueskyActor, createdAt: Date? = nil) {
        id = recordURI
        self.recordURI = recordURI
        self.actor = actor
        // Falls back to parsing the record creation timestamp from the URI's TID component.
        self.createdAt = createdAt ?? Self.extractTimestampFromURI(recordURI)
    }

    // MARK: - Private Helpers

    /// Decodes the Bluesky TID (timestamp ID) from a record URI to extract the creation date.
    /// TIDs are 13-character base-32 encoded strings where the lower 53 bits represent microsecond timestamps.
    /// - Parameter uri: The full AT record URI.
    /// - Returns: The decoded date, or nil if parsing fails.
    private static func extractTimestampFromURI(_ uri: String) -> Date? {
        let tidChars = "234567abcdefghijklmnopqrstuvwxyz"
        var charToValue: [Character: UInt64] = [:]
        for (i, c) in tidChars.enumerated() {
            charToValue[c] = UInt64(i)
        }
        // TID is the last path component and must be exactly 13 characters.
        guard let tid = uri.split(separator: "/").last, tid.count == 13 else { return nil }
        var value: UInt64 = 0
        for c in tid {
            guard let v = charToValue[c] else { return nil }
            value = (value << 5) | v
        }
        // Lower 53 bits encode the microsecond timestamp per the AT Protocol spec.
        let timestampMicros = value & ((1 << 53) - 1)
        return Date(timeIntervalSince1970: Double(timestampMicros) / 1_000_000)
    }
}
