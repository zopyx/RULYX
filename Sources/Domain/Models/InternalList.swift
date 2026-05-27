import SwiftUI

/// Represents a locally-created list that is not synced to Bluesky.
/// Used for internal organization and color-coded grouping of actors.
struct InternalList: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// A unique identifier for this local list.
    let id: UUID
    /// The display name of this internal list.
    var name: String
    /// The color used to visually identify this list.
    var color: InternalListColor
    /// The actors that are members of this internal list.
    var members: [InternalListMember]
    /// The date this list was created.
    let createdAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        color: InternalListColor,
        members: [InternalListMember] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.members = members
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// The number of members in this list (computed from the members array).
    var memberCount: Int {
        members.count
    }
}

/// Represents a single actor stored in an internal (local) list.
struct InternalListMember: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// The DID of the actor (used as the unique identifier).
    let id: String
    /// The Bluesky handle of the member.
    let handle: String
    /// The display name of the member, if available.
    let displayName: String?
    /// The URL string of the member's avatar image.
    let avatarURL: String?
    /// The date this member was added to the list.
    let addedAt: Date

    // MARK: - Init

    init(
        did: String,
        handle: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        addedAt: Date = .now
    ) {
        id = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.addedAt = addedAt
    }
}

/// Defines the available colors for an internal list.
/// Used to visually differentiate lists and their associated UI elements.
enum InternalListColor: String, Codable, CaseIterable, Hashable {
    case red
    case green
    case blue
    case orange
    case purple
    case yellow

    /// Returns the SF Symbol name for a filled circle, used as a color indicator icon.
    var symbolName: String {
        switch self {
        case .red: "circle.fill"
        case .green: "circle.fill"
        case .blue: "circle.fill"
        case .orange: "circle.fill"
        case .purple: "circle.fill"
        case .yellow: "circle.fill"
        }
    }
}

extension InternalListColor {
    /// The SwiftUI Color value corresponding to this enum case.
    var colorValue: Color {
        switch self {
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .orange: .orange
        case .purple: .purple
        case .yellow: .yellow
        }
    }
}
