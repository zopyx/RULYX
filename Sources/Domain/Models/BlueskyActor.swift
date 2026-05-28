import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Represents a minimal Bluesky actor with core profile information.
/// Used as a lightweight representation of a user in contexts like list memberships and block lists.
struct BlueskyActor: Identifiable, Hashable, Codable {
    // MARK: - Properties

    /// The unique identifier for this actor. When `id` is not provided during init, it defaults to the DID.
    let id: String
    /// The decentralized identifier (DID) for this actor.
    let did: String
    /// The Bluesky handle (e.g., `alice.bsky.social`).
    let handle: String
    /// The display name, if available.
    let displayName: String?
    /// The URL to the actor's avatar image.
    let avatarURL: URL?
    /// The date the actor's account was created on Bluesky.
    let createdAt: Date?
    /// The date this actor was blocked, if applicable (set when fetched from block lists).
    var blockedDate: Date?
    /// A short description/bio for this actor, if available.
    var description: String?

    // MARK: - Init

    init(
        id: String? = nil,
        did: String,
        handle: String,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        createdAt: Date? = nil,
        blockedDate: Date? = nil,
        description: String? = nil
    ) {
        self.id = id ?? did
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.blockedDate = blockedDate
        self.description = description
    }

    // MARK: - Computed Properties

    /// Returns the display name if available and non-empty; falls back to the handle.
    var title: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return handle
    }

    /// Whether this actor's account was created within the last 28 days (approximately one month).
    /// Used as a heuristic for detecting newly-created accounts.
    var isNew: Bool {
        guard let createdAt else { return false }
        let fourWeeksAgo = Date.now.addingTimeInterval(-28 * 86400)
        return createdAt > fourWeeksAgo
    }
}
