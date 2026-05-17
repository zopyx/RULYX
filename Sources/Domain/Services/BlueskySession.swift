import Foundation

struct BlueskySession: Codable {
    let did: String
    let handle: String
    let accessJWT: String
    let refreshJWT: String?
    let pdsURL: URL
}

struct PagedListMembers {
    let members: [BlueskyListMember]
    let cursor: String?
}

struct PagedActorSearch {
    let actors: [BlueskyActor]
    let cursor: String?
}

@MainActor
protocol BlueskyAuthenticating {
    func authenticate(handle: String, appPassword: String, entrywayURL: URL?) async throws -> BlueskySession
    func persistSession(_ session: BlueskySession, for account: AppAccount) async throws
    func deletePersistedSession(for account: AppAccount) throws
}
