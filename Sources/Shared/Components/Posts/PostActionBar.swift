import SwiftUI

struct PostActionBar: View {
    let replyCount: Int?
    let repostCount: Int?
    let likeCount: Int?
    var isLiked: Bool
    var isReposted: Bool
    let callbacks: PostRowCallbacks

    private var moderationLikerTargetLists: [BlueskyList] {
        callbacks.availableLikerTargetLists.filter { $0.kind == .moderation }
    }

    private var internalLikerTargetLists: [BlueskyList] {
        callbacks.availableLikerTargetLists.filter { $0.kind == .internal }
    }

    private var regularLikerTargetLists: [BlueskyList] {
        callbacks.availableLikerTargetLists.filter { $0.kind == .regular }
    }

    var body: some View {
        HStack(spacing: 24) {
            if let onReply = callbacks.onReply {
                actionButton(icon: "bubble.left", count: replyCount, action: onReply)
            }
            if let onRepost = callbacks.onRepost {
                Button(action: { onRepost() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isReposted ? "repeat.circle.fill" : "repeat")
                            .font(.body.weight(.medium))
                        if let count = repostCount {
                            Text("\(count)")
                                .font(.callout)
                        }
                    }
                    .foregroundStyle(isReposted ? Color.green : Color.gray.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                if let onLike = callbacks.onLike {
                    Button(action: { onLike() }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.body.weight(.medium))
                            .foregroundStyle(isLiked ? Color.red : Color.gray.opacity(0.6))
                    }
                }
                if let count = likeCount {
                    Button(action: { callbacks.onShowLikes?() }) {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            if let onQuote = callbacks.onQuote {
                actionButton(icon: "quote.bubble", count: nil, action: onQuote)
            }
            Spacer()
            if hasGearMenuItems {
                gearMenu
            }
        }
        .foregroundStyle(.tertiary)
    }

    private var hasGearMenuItems: Bool {
        callbacks.onBlockAllLikers != nil
            || (!callbacks.availableLikerTargetLists.isEmpty && callbacks.onAddAllLikersToList != nil)
            || callbacks.onClassify != nil
            || callbacks.onCopy != nil
            || callbacks.onTranslate != nil
            || callbacks.onReportPost != nil
            || callbacks.onEditPost != nil
            || callbacks.onDeletePost != nil
    }

    private var gearMenu: some View {
        Menu {
            if let onBlockAllLikers = callbacks.onBlockAllLikers {
                Button {
                    onBlockAllLikers()
                } label: {
                    Label {
                        Text(loc: "post.block_likers")
                    } icon: {
                        Image(systemName: "hand.raised.slash")
                    }
                }
            }
            if let onAddAllLikersToList = callbacks.onAddAllLikersToList, !callbacks.availableLikerTargetLists.isEmpty {
                Menu {
                    if !moderationLikerTargetLists.isEmpty {
                        Menu {
                            ForEach(moderationLikerTargetLists) { list in
                                Button {
                                    onAddAllLikersToList(list)
                                } label: {
                                    Label(list.name, systemImage: list.kind.symbolName)
                                }
                            }
                        } label: {
                            Text(loc: "lists.moderation_lists")
                        }
                    }
                    if !internalLikerTargetLists.isEmpty {
                        Menu {
                            ForEach(internalLikerTargetLists) { list in
                                Button {
                                    onAddAllLikersToList(list)
                                } label: {
                                    Label(list.name, systemImage: list.kind.symbolName)
                                }
                            }
                        } label: {
                            Text(loc: "lists.internal_lists")
                        }
                    }
                    if !regularLikerTargetLists.isEmpty {
                        Menu {
                            ForEach(regularLikerTargetLists) { list in
                                Button {
                                    onAddAllLikersToList(list)
                                } label: {
                                    Label(list.name, systemImage: list.kind.symbolName)
                                }
                            }
                        } label: {
                            Text(loc: "lists.lists")
                        }
                    }
                } label: {
                    Label {
                        Text(loc: "post.add_likers_to_list")
                    } icon: {
                        Image(systemName: "text.badge.plus")
                    }
                }
            }
            if let onClassify = callbacks.onClassify {
                Button(action: onClassify) {
                    Label {
                        Text(loc: "post.classify")
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }
            }
            if let onCopy = callbacks.onCopy {
                Button(action: onCopy) {
                    Label {
                        Text(loc: "post.copy")
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            if let onTranslate = callbacks.onTranslate {
                Button(action: onTranslate) {
                    Label {
                        Text(loc: "post.translate")
                    } icon: {
                        Image(systemName: "globe")
                    }
                }
            }
            if let onReportPost = callbacks.onReportPost {
                Button(action: onReportPost) {
                    Label {
                        Text(loc: "post.report")
                    } icon: {
                        Image(systemName: "exclamationmark.shield")
                    }
                }
            }
            if callbacks.onEditPost != nil || callbacks.onDeletePost != nil {
                Divider()
            }
            if let onEditPost = callbacks.onEditPost {
                Button(action: onEditPost) {
                    Label {
                        Text(loc: "post.edit")
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
            }
            if let onDeletePost = callbacks.onDeletePost {
                Button(role: .destructive, action: onDeletePost) {
                    Label {
                        Text(loc: "post.delete")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .accessibilityLabel(loc("post.gear_menu"))
    }

    @ViewBuilder
    private func actionButton(icon: String, count: Int?, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                    if let count {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                if let count {
                    Text("\(count)")
                        .font(.callout)
                }
            }
        }
    }
}
