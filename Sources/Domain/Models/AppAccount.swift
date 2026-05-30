import Foundation

/// Represents a Bluesky account stored in the app.
/// Persisted via Codable; secrets (password/session) are stored separately in the keychain.
struct AppAccount: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// A unique identifier for this stored account.
    let id: UUID
    /// The Bluesky handle associated with this account.
    var handle: String
    /// The display name shown in the account UI; defaults to the handle if no display name is set.
    var displayName: String
    /// The decentralized identifier (DID), populated after successful authentication.
    var did: String?
    /// The URL to the account's Bluesky avatar image.
    var avatarURL: URL?
    /// The Personal Data Server URL for this account (e.g., `https://bsky.social`).
    var pdsURL: URL?
    /// The entryway/app password URL, if different from the PDS URL.
    var entrywayURL: URL?
    /// An optional user-assigned label to distinguish multiple accounts.
    var label: String?
    /// An optional accent tint color identifier ("blue", "green", "orange", "purple", "red", "teal", "pink").
    var tintColor: String?
    /// The date this account was added to the app.
    var createdAt: Date
    /// The date this account was last used for an operation.
    var lastUsedAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        handle: String,
        displayName: String? = nil,
        did: String? = nil,
        avatarURL: URL? = nil,
        pdsURL: URL? = nil,
        entrywayURL: URL? = nil,
        label: String? = nil,
        createdAt: Date = .now,
        lastUsedAt: Date = .now
    ) {
        self.id = id
        self.handle = handle
        // Falls back to the handle when no display name is provided.
        self.displayName = displayName ?? handle
        self.did = did
        self.avatarURL = avatarURL
        self.pdsURL = pdsURL
        self.entrywayURL = entrywayURL
        self.label = label
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
