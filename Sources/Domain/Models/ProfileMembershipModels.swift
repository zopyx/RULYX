import Foundation

struct ProfileListMembership: Identifiable, Hashable {
    let id: String
    let listURI: String
    let name: String
    let kind: BlueskyList.Kind
    let memberCount: Int?
    let isMember: Bool
    let listItemRecordURI: String?

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

struct ProfileStarterPackMembership: Identifiable, Hashable {
    let id: String
    let uri: String
    let name: String
    let memberCount: Int?
    let joinedAllTimeCount: Int?
    let isMember: Bool

    init(uri: String, name: String, memberCount: Int?, joinedAllTimeCount: Int?, isMember: Bool) {
        id = uri
        self.uri = uri
        self.name = name
        self.memberCount = memberCount
        self.joinedAllTimeCount = joinedAllTimeCount
        self.isMember = isMember
    }
}

struct ProfileInspection: Hashable {
    let profile: BlueskyProfile
    let listMemberships: [ProfileListMembership]
    let starterPackMemberships: [ProfileStarterPackMembership]
}
