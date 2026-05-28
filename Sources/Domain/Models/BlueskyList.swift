import Foundation

/// Represents a Bluesky moderation or curation list fetched from the AT Protocol.
/// Lists can group actors for bulk moderation or organizational purposes.
struct BlueskyList: Identifiable, Hashable, Codable {
    // MARK: - Enums

    /// Categorizes the list type based on its Bluesky purpose identifier.
    enum Kind: String, CaseIterable, Hashable, Codable {
        /// A moderation list (`app.bsky.graph.defs#modlist`) — used for blocking/muting members in bulk.
        case moderation
        /// A curation list (`app.bsky.graph.defs#curatelist`) — used for internal organization.
        case `internal`
        /// A regular curation list — used for general grouping purposes.
        case regular

        // MARK: - Computed Properties

        /// Numeric sort order: moderation (0), internal (1), regular (2).
        var sortOrder: Int {
            switch self {
            case .moderation: 0
            case .internal: 1
            case .regular: 2
            }
        }

        /// Localized display title for this list kind.
        @MainActor
        var title: String {
            switch self {
            case .moderation:
                String.localized("list.kind.moderation")
            case .internal:
                String.localized("list.kind.internal")
            case .regular:
                String.localized("list.kind.regular")
            }
        }

        /// SF Symbol name used to visually represent this list kind.
        var symbolName: String {
            switch self {
            case .moderation:
                "shield.lefthalf.filled"
            case .internal:
                "tray.full"
            case .regular:
                "person.3"
            }
        }

        /// The AT Protocol lexicon purpose identifier for this list kind.
        var purposeIdentifier: String {
            switch self {
            case .moderation:
                "app.bsky.graph.defs#modlist"
            case .internal:
                "app.bsky.graph.defs#curatelist"
            case .regular:
                "app.bsky.graph.defs#curatelist"
            }
        }
    }

    // MARK: - Properties

    /// The AT URI of this list (e.g., `at://did:plc:.../app.bsky.graph.list/...`).
    let id: String
    /// The display name of this list.
    var name: String
    /// The description of this list.
    var description: String
    /// The number of members in this list, if available.
    let memberCount: Int?
    /// The classification of this list (moderation, internal, regular).
    let kind: Kind
    /// The URL to the list's avatar image.
    var avatarURL: URL?
    /// The content hash (CID) for this list record, if available.
    let cid: String?

    // MARK: - Init

    init(
        id: String,
        name: String,
        description: String,
        memberCount: Int?,
        kind: Kind,
        avatarURL: URL? = nil,
        cid: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.memberCount = memberCount
        self.kind = kind
        self.avatarURL = avatarURL
        self.cid = cid
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, description, memberCount, kind, avatarURL, cid
    }
}
