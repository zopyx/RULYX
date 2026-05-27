import Foundation

// MARK: - PostRowCallbacks

/// Aggregates all user-action callbacks and state overrides for a post row.
/// Each optional closure is wired by the parent view; when `nil`, the corresponding UI element is hidden.
struct PostRowCallbacks {
    /// Navigate to the post's thread/detail view.
    var onTapThread: (() -> Void)?
    /// Open full-screen image carousel at the given index.
    var onTapImage: ((Int) -> Void)?
    /// Play embedded video.
    var onPlayVideo: (() -> Void)?
    /// Open the author's profile (parameter is DID or handle string).
    var onOpenProfile: ((String) -> Void)?
    /// Open an external URL from the post or its embed.
    var onOpenURL: ((URL) -> Void)?
    /// Open the reply compose sheet.
    var onReply: (() -> Void)?
    /// Toggle like state.
    var onLike: (() -> Void)?
    /// Show the list of users who liked this post.
    var onShowLikes: (() -> Void)?
    /// Toggle repost state.
    var onRepost: (() -> Void)?
    /// Open the compose sheet with a quote of this post.
    var onQuote: (() -> Void)?
    /// Copy the post text to the pasteboard.
    var onCopy: (() -> Void)?
    /// Translate the post content via AI.
    var onTranslate: (() -> Void)?
    /// Delete the post (destructive action).
    var onDeletePost: (() -> Void)?
    /// Open the compose sheet in edit mode for this post.
    var onEditPost: (() -> Void)?
    /// Report the post via API or email.
    var onReportPost: (() -> Void)?
    /// Block all users who liked the post (batch operation).
    var onBlockAllLikers: (() -> Void)?
    /// Add all users who liked the post to the given Bluesky list.
    var onAddAllLikersToList: ((BlueskyList) -> Void)?
    /// Classify the post using AI.
    var onClassify: (() -> Void)?

    /// Override for the liked state (e.g. when optimistic updates or preview data differ from server).
    var isLiked: Bool = false
    /// Override for the reposted state.
    var isReposted: Bool = false
    /// Override for the like count display (e.g. during optimistic updates).
    var overrideLikeCount: Int?
    /// Override for the repost count display.
    var overrideRepostCount: Int?
    /// Lists available as targets for "add all likers" operations.
    var availableLikerTargetLists: [BlueskyList] = []

    // MARK: - Init

    init(
        onTapThread: (() -> Void)? = nil,
        onTapImage: ((Int) -> Void)? = nil,
        onPlayVideo: (() -> Void)? = nil,
        onOpenProfile: ((String) -> Void)? = nil,
        onOpenURL: ((URL) -> Void)? = nil,
        onReply: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onShowLikes: (() -> Void)? = nil,
        onRepost: (() -> Void)? = nil,
        onQuote: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onTranslate: (() -> Void)? = nil,
        onDeletePost: (() -> Void)? = nil,
        onEditPost: (() -> Void)? = nil,
        onReportPost: (() -> Void)? = nil,
        onBlockAllLikers: (() -> Void)? = nil,
        onAddAllLikersToList: ((BlueskyList) -> Void)? = nil,
        onClassify: (() -> Void)? = nil,
        isLiked: Bool = false,
        isReposted: Bool = false,
        overrideLikeCount: Int? = nil,
        overrideRepostCount: Int? = nil,
        availableLikerTargetLists: [BlueskyList] = []
    ) {
        self.onTapThread = onTapThread
        self.onTapImage = onTapImage
        self.onPlayVideo = onPlayVideo
        self.onOpenProfile = onOpenProfile
        self.onOpenURL = onOpenURL
        self.onReply = onReply
        self.onLike = onLike
        self.onShowLikes = onShowLikes
        self.onRepost = onRepost
        self.onQuote = onQuote
        self.onCopy = onCopy
        self.onTranslate = onTranslate
        self.onDeletePost = onDeletePost
        self.onEditPost = onEditPost
        self.onReportPost = onReportPost
        self.onBlockAllLikers = onBlockAllLikers
        self.onAddAllLikersToList = onAddAllLikersToList
        self.onClassify = onClassify
        self.isLiked = isLiked
        self.isReposted = isReposted
        self.overrideLikeCount = overrideLikeCount
        self.overrideRepostCount = overrideRepostCount
        self.availableLikerTargetLists = availableLikerTargetLists
    }
}
