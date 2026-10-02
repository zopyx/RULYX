import Foundation

// MARK: - Blocklist

/// One block entry (DID + block date), shared by both blocklist sources: the account's own
/// repo records and the Constellation index.
struct BlocklistEntry: Codable, Sendable {
    let did: String
    /// ISO 8601 date string of when the block was created.
    let blockedDate: String

    enum CodingKeys: String, CodingKey {
        case did
        case blockedDate = "blocked_date"
    }
}

// MARK: - Listed on

/// One list a profile appears on, as the "Listed on" screen renders it.
struct ListedOnListEntry: Decodable, Identifiable {
    let name: String
    let description: String?
    /// DID of the list's owner.
    let did: String
    /// AT-URI of the list.
    let url: String
    /// ISO 8601 creation date of the *list*, when known.
    let createdDate: String
    /// ISO 8601 date the profile was added to the list.
    let dateAdded: String

    var id: String {
        url
    }
}

/// Progress of a "Listed on" lookup, so the UI can show what is still running.
///
/// The lookup has two phases with very different costs: walking the index for the profile's
/// memberships (a known number of pages, unknown total) and then resolving the list metadata
/// per owning repo (one AppView request per owner, the expensive part).
enum ListedOnProgress: Sendable, Equatable {
    /// Walking the index for the profile's `app.bsky.graph.listitem` records.
    case memberships
    /// Resolving list metadata: how many of the memberships' lists are resolved, out of how many.
    case lists(resolved: Int, total: Int)

    /// Completion of the metadata phase, or `nil` while the total is not known yet — the UI
    /// shows an indeterminate spinner then.
    var fraction: Double? {
        guard case let .lists(resolved, total) = self, total > 0 else { return nil }
        return min(1, max(0, Double(resolved) / Double(total)))
    }
}
