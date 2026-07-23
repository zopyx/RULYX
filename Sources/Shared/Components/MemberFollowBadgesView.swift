import SwiftUI

// MARK: - MemberFollowBadgesView

/// Displays relationship-status pill badges for a given viewer state.
///
/// Badges shown (when relevant):
/// - "Following" (blue) — current user follows this actor
/// - "Follows me" (green) — this actor follows the current user
/// - "Blocking" (orange) — current user blocks this actor
/// - "Blocks me" (red) — this actor blocks the current user
///
/// Renders nothing when viewerState is nil or no relationship is true.
struct MemberFollowBadgesView: View {
    let viewerState: BlueskyViewerState?

    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        if let state = viewerState {
            HStack(spacing: 3) {
                if state.isFollowing {
                    Text(loc("profile.badge.following"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
                if state.followsYou {
                    Text(loc("profile.badge.follows_me"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.12), in: Capsule())
                }
                if state.isBlocking {
                    Text(loc("profile.badge.blocking"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                if state.blockedBy {
                    Text(loc("profile.badge.blocks_me"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

// MARK: - Convenience extensions

extension BlueskyViewerState {
    /// Returns an updated viewer state with isFollowing and followingRecordURI overridden
    /// to reflect an optimistic follow action.
    func withOptimisticFollow(following: Bool, recordURI: String? = nil) -> BlueskyViewerState {
        BlueskyViewerState(
            muted: muted,
            blockedBy: blockedBy,
            isBlocking: isBlocking,
            blockingRecordURI: blockingRecordURI,
            isFollowing: following,
            followingRecordURI: following ? (recordURI ?? followingRecordURI) : nil,
            followsYou: followsYou,
            mutedByListName: mutedByListName,
            blockingByListName: blockingByListName
        )
    }
}

#Preview {
    VStack(spacing: 8) {
        // Following only
        MemberFollowBadgesView(viewerState: BlueskyViewerState(
            muted: false, blockedBy: false, isBlocking: false,
            blockingRecordURI: nil,
            isFollowing: true, followingRecordURI: "at://...",
            followsYou: false,
            mutedByListName: nil, blockingByListName: []
        ))
        // Follows me only
        MemberFollowBadgesView(viewerState: BlueskyViewerState(
            muted: false, blockedBy: false, isBlocking: false,
            blockingRecordURI: nil,
            isFollowing: false, followingRecordURI: nil,
            followsYou: true,
            mutedByListName: nil, blockingByListName: []
        ))
        // Blocking only
        MemberFollowBadgesView(viewerState: BlueskyViewerState(
            muted: false, blockedBy: false, isBlocking: true,
            blockingRecordURI: "at://...",
            isFollowing: false, followingRecordURI: nil,
            followsYou: false,
            mutedByListName: nil, blockingByListName: []
        ))
        // Blocks me only
        MemberFollowBadgesView(viewerState: BlueskyViewerState(
            muted: false, blockedBy: true, isBlocking: false,
            blockingRecordURI: nil,
            isFollowing: false, followingRecordURI: nil,
            followsYou: false,
            mutedByListName: nil, blockingByListName: []
        ))
        // All four
        MemberFollowBadgesView(viewerState: BlueskyViewerState(
            muted: false, blockedBy: true, isBlocking: true,
            blockingRecordURI: "at://...",
            isFollowing: true, followingRecordURI: "at://...",
            followsYou: true,
            mutedByListName: nil, blockingByListName: []
        ))
    }
    .padding()
}
