import Foundation

struct BlueskyActor: Identifiable, Hashable, Codable {
    let id: String
    let did: String
    let handle: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date?
    var blockedDate: Date?
    var description: String?

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

    var title: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return handle
    }

    var isNew: Bool {
        guard let createdAt else { return false }
        let fourWeeksAgo = Date.now.addingTimeInterval(-28 * 86400)
        return createdAt > fourWeeksAgo
    }
}
