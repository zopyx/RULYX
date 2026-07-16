import SwiftUI

// MARK: - TimelinePostRowContext

/// Callbacks for the context menu and swipe actions surrounding a post row in a timeline.
struct TimelinePostRowContext {
    /// Called when the user taps "Copy" in the context menu.
    var onCopyText: (() -> Void)?
    /// Called when the user taps "Share" in the context menu.
    var onShare: (() -> Void)?
    /// Called when the user taps "Mute User" in the context menu.
    var onMuteUser: (() -> Void)?
    /// Called when the user taps "Block User" in the context menu.
    var onBlockUser: (() -> Void)?
    /// Called when the user taps "Report" in the context menu.
    var onReportPost: (() -> Void)?
    /// Called when the user taps "Translate" in the context menu.
    var onTranslate: (() -> Void)?
    /// Called when the user taps "Mute Word" in the context menu. Only shown if non-nil.
    var onMuteWord: (() -> Void)?

    /// The word to show in the "Mute Word" context menu item, if applicable.
    var muteWordLabel: String?

    /// Called when the user taps to expand/collapse the inline thread.
    var onToggleInlineThread: (() -> Void)?
}

// MARK: - TimelinePostRow

/// A self-contained post row for timeline views — wraps `PostRowView` with
/// context menu, swipe actions, inline thread expansion, and AI classification badge.
///
/// Both `FeedTimelineView` and `ListTimelineView` use this component to avoid
/// duplicating ~60 lines of post-row boilerplate.
struct TimelinePostRow: View {
    let entry: RichFeedEntry
    let callbacks: PostRowCallbacks
    let context: TimelinePostRowContext
    let viewModel: any TimelineViewModelProtocol
    @Binding var navigationPath: NavigationPath
    let aiClassifications: [String: [String: Double]]
    let isOwnPost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostRowView(
                entry: entry,
                style: .full,
                callbacks: callbacks
            )
            .contextMenu { contextMenuContent }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    callbacks.onLike?()
                } label: {
                    Image(systemName: callbacks.isLiked ? "heart.slash" : "heart")
                }
                .tint(callbacks.isLiked ? .gray : .pink)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    callbacks.onReply?()
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .tint(.blue)
            }

            if let scores = aiClassifications[entry.post.uri], !scores.isEmpty {
                AIPostBadge(scores: scores)
                    .padding(.leading, 12)
                    .padding(.bottom, 4)
            }

            inlineThreadSection
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if let onCopy = context.onCopyText {
            Button(action: onCopy) {
                Label(loc("post.copy"), systemImage: "doc.on.doc")
            }
        }
        if let onShare = context.onShare {
            Button(action: onShare) {
                Label(loc("post.share"), systemImage: "square.and.arrow.up")
            }
        }
        if context.onMuteUser != nil || context.onBlockUser != nil {
            Divider()
        }
        if let onMute = context.onMuteUser {
            Button(action: onMute) {
                Label(loc("post.mute_user"), systemImage: "eye.slash")
            }
        }
        if let onBlock = context.onBlockUser {
            Button(action: onBlock) {
                Label(loc("post.block_user"), systemImage: "hand.raised")
            }
        }
        if context.onReportPost != nil || context.onTranslate != nil {
            Divider()
        }
        if !isOwnPost, let onReport = context.onReportPost {
            Button(action: onReport) {
                Label(loc("post.report"), systemImage: "exclamationmark.bubble")
            }
        }
        if let onTranslate = context.onTranslate {
            Button(action: onTranslate) {
                Label(loc("post.translate"), systemImage: "globe")
            }
        }
        if let onMuteWord = context.onMuteWord, let word = context.muteWordLabel {
            Divider()
            Button(action: onMuteWord) {
                Label(
                    loc("timeline.mute_word").replacingOccurrences(of: "{word}", with: word),
                    systemImage: "textformat.subscript"
                )
            }
        }
    }

    // MARK: - Inline Thread

    @ViewBuilder
    private var inlineThreadSection: some View {
        let uri = entry.post.uri
        let replyCount = entry.post.replyCount ?? 0
        if replyCount > 0 {
            if viewModel.expandedThreadURIs.contains(uri), let thread = viewModel.inlineThreads[uri] {
                VStack(spacing: 0) {
                    ForEach(Array((thread.replies ?? []).prefix(3).enumerated()), id: \.offset) { _, reply in
                        InlineReplyRow(node: reply, onNavigateToThread: {
                            navigationPath.append(TimelineRoute.thread(postURI: reply.post.uri ?? uri))
                        })
                        .padding(.leading, 16)
                    }
                    if (thread.replies?.count ?? 0) > 3 {
                        Button {
                            navigationPath.append(TimelineRoute.thread(postURI: uri))
                        } label: {
                            HStack {
                                Text(loc("timeline.view_all_replies"))
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("+\((thread.replies?.count ?? 0) - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button {
                    context.onToggleInlineThread?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.caption)
                        Text(loc("timeline.show_replies").replacingOccurrences(of: "{n}", with: "\(replyCount)"))
                            .font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.skyPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.skyPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
