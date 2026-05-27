import Foundation

/// Represents a Bluesky list and whether the inspected profile is a member of it.
/// Used on the profile inspection screen to show which lists contain the profile.
struct ProfileListMembership: Identifiable, Hashable {
    // MARK: - Properties

    /// The AT URI of the list (used as the unique identifier).
    let id: String
    /// The full AT URI of the list record.
    let listURI: String
    /// The display name of the list.
    let name: String
    /// The kind of list (moderation, internal, regular).
    let kind: BlueskyList.Kind
    /// The total number of members in this list, if available.
    let memberCount: Int?
    /// Whether the inspected profile is currently a member of this list.
    let isMember: Bool
    /// The AT URI of the list item record, if the profile is a member. Nil if the profile is not a member.
    let listItemRecordURI: String?

    // MARK: - Init

    init(
        listURI: String,
        name: String,
        kind: BlueskyList.Kind,
        memberCount: Int?,
        isMember: Bool,
        listItemRecordURI: String?
    ) {
        id = listURI
        self.listURI = listURI
        self.name = name
        self.kind = kind
        self.memberCount = memberCount
        self.isMember = isMember
        self.listItemRecordURI = listItemRecordURI
    }
}

/// Represents a starter pack and whether the inspected profile has joined it.
/// Used on the profile inspection screen to show starter pack memberships.
struct ProfileStarterPackMembership: Identifiable, Hashable {
    // MARK: - Properties

    /// The AT URI of the starter pack (used as the unique identifier).
    let id: String
    /// The full AT URI of the starter pack record.
    let uri: String
    /// The display name of the starter pack.
    let name: String
    /// The current number of members in this starter pack, if available.
    let memberCount: Int?
    /// The total number of people who have ever joined this starter pack, if available.
    let joinedAllTimeCount: Int?
    /// Whether the inspected profile is a member of this starter pack.
    let isMember: Bool

    // MARK: - Init

    init(uri: String, name: String, memberCount: Int?, joinedAllTimeCount: Int?, isMember: Bool) {
        id = uri
        self.uri = uri
        self.name = name
        self.memberCount = memberCount
        self.joinedAllTimeCount = joinedAllTimeCount
        self.isMember = isMember
    }
}

/// Aggregates a profile's inspection data, including its Bluesky profile,
/// list memberships, and starter pack memberships.
struct ProfileInspection: Hashable {
    // MARK: - Properties

    /// The full Bluesky profile for the inspected account.
    let profile: BlueskyProfile
    /// The lists this profile is a member of (and related lists it is not a member of).
    let listMemberships: [ProfileListMembership]
    /// The starter packs this profile has joined.
    let starterPackMemberships: [ProfileStarterPackMembership]
}
