import Foundation

struct ComposeContext: Identifiable {
    let id = UUID()
    let account: AppAccount
    let appPassword: String
    let isReply: Bool
    var parentURI: String = ""
    var parentCID: String = ""
    var rootURI: String = ""
    var rootCID: String = ""
    var uri: String = ""
    var cid: String = ""
}
