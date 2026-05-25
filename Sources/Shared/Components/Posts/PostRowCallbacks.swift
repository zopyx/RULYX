import Foundation

struct PostRowCallbacks {
    var onTapThread: (() -> Void)?
    var onTapImage: ((Int) -> Void)?
    var onPlayVideo: (() -> Void)?
    var onOpenProfile: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onReply: (() -> Void)?
    var onLike: (() -> Void)?
    var onShowLikes: (() -> Void)?
    var onRepost: (() -> Void)?
    var onQuote: (() -> Void)?
    var onCopy: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onDeletePost: (() -> Void)?
    var onEditPost: (() -> Void)?
    var onReportPost: (() -> Void)?
    var onBlockAllLikers: (() -> Void)?
    var onAddAllLikersToList: ((BlueskyList) -> Void)?
    var onClassify: (() -> Void)?
    var isLiked: Bool = false
    var isReposted: Bool = false
    var overrideLikeCount: Int?
    var overrideRepostCount: Int?
    var availableLikerTargetLists: [BlueskyList] = []

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
