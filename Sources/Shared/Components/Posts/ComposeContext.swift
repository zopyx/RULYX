import Foundation

// MARK: - ComposeContext

/// Metadata for the compose flow — which account is posting, reply/quote context URIs,
/// and edit state. Populated by the calling view and passed to the compose sheet.
struct ComposeContext: Identifiable {
    let id = UUID()
    /// The account that will own the new post.
    let account: AppAccount
    /// The app password for authentication.
    let appPassword: String
    /// Whether this is a reply to an existing post.
    let isReply: Bool
    /// URI of the parent post being replied to.
    var parentURI: String = ""
    /// CID of the parent post being replied to.
    var parentCID: String = ""
    /// URI of the root post in the thread (for nested replies).
    var rootURI: String = ""
    /// CID of the root post in the thread.
    var rootCID: String = ""
    /// URI of the post being edited (empty for new posts).
    var uri: String = ""
    /// CID of the post being edited.
    var cid: String = ""
}
