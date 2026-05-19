import Foundation

struct BlueskyList: Identifiable, Hashable, Codable {
    enum Kind: String, CaseIterable, Hashable, Codable {
        case moderation
        case regular

        @MainActor
        var title: String {
            switch self {
            case .moderation:
                String.localized("list.kind.moderation")
            case .regular:
                String.localized("list.kind.regular")
            }
        }

        var symbolName: String {
            switch self {
            case .moderation:
                "shield.lefthalf.filled"
            case .regular:
                "person.3"
            }
        }

        var purposeIdentifier: String {
            switch self {
            case .moderation:
                "app.bsky.graph.defs#modlist"
            case .regular:
                "app.bsky.graph.defs#curatelist"
            }
        }
    }

    let id: String
    var name: String
    var description: String
    let memberCount: Int?
    let kind: Kind
    var avatarURL: URL? = nil
    let cid: String?

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

    enum CodingKeys: String, CodingKey {
        case id, name, description, memberCount, kind, avatarURL, cid
    }
}
