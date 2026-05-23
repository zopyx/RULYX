import Foundation

struct SubscribedListInfo: Identifiable {
    let id: String
    let listURI: String
    let name: String
    let description: String?
    let ownerDID: String
    let ownerHandle: String
    let ownerDisplayName: String?
    let memberCount: Int?
    let kind: BlueskyList.Kind
    let subscribedAt: Date?
}
