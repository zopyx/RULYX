import Foundation
import Observation

/// Protocol defining the common contract for all timeline view models.
///
/// All timeline implementations (feed, list, custom) SHALL conform to this protocol,
/// enabling shared UI components to consume any timeline without knowing the data source.
@MainActor
protocol TimelineViewModelProtocol: AnyObject {
    // MARK: - Core State

    /// All loaded timeline entries.
    var entries: [RichFeedEntry] { get }

    /// Current lifecycle state (loading/loaded/empty/error/exhausted).
    var state: TimelineState { get }

    /// Count of new posts discovered since the last refresh (0 when polling inactive).
    var newPostCount: Int { get set }

    /// Set of post URIs with inline thread expanded.
    var expandedThreadURIs: Set<String> { get set }

    /// Cached inline thread nodes keyed by post URI.
    var inlineThreads: [String: ThreadNode] { get set }

    /// Optional progress label shown during scanning/loading.
    var scanProgressLabel: String? { get }

    // MARK: - Loading

    /// Performs the initial timeline load. Only fires when in `.initialLoading` state.
    func loadTimeline(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async

    /// Loads the next page of timeline entries.
    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async

    /// Pull-to-refresh: resets optimistic state and reloads the first page.
    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async

    // MARK: - Polling

    /// Starts background polling for new posts at the given interval.
    func startPolling(account: AppAccount, appPassword: String, using client: LiveBlueskyClient, interval: TimeInterval)

    /// Cancels the active polling task.
    func stopPolling()

    /// Notifies the polling system of user interaction (resets adaptive interval).
    func userDidInteract()

    // MARK: - Optimistic Interactions

    /// Returns the effective like state, preferring optimistic value over server data.
    func effectiveIsLiked(uri: String) -> Bool

    /// Returns the effective repost state, preferring optimistic value over server data.
    func effectiveIsReposted(uri: String) -> Bool

    /// Returns the effective like count, preferring optimistic value over server data.
    func effectiveLikeCount(uri: String) -> Int

    /// Returns the effective repost count, preferring optimistic value over server data.
    func effectiveRepostCount(uri: String) -> Int

    /// Optimistically toggles like. Rolls back on failure.
    func toggleLike(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async

    /// Optimistically toggles repost. Rolls back on failure.
    func toggleRepost(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async

    // MARK: - Inline Threads

    /// Toggles inline thread expansion for a post URI. Uses ThreadCacheService.
    func toggleInlineThread(uri: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async

    // MARK: - Mutations

    /// Removes an entry from the timeline by URI (e.g. after deletion).
    func removeEntry(uri: String)

    /// Inserts an entry at the given index (used for optimistic post creation).
    func insertEntry(_ entry: RichFeedEntry, at index: Int)

    /// Resets all state for an account switch.
    func prepareForAccountChange()
}

// MARK: - Default Implementations

extension TimelineViewModelProtocol {
    /// Whether the timeline is currently fetching data.
    var isLoading: Bool {
        state.isLoading
    }

    /// Whether more pages can be loaded.
    var hasMore: Bool {
        state.hasMore
    }

    /// Optional progress label (nil by default for feed timelines).
    var scanProgressLabel: String? {
        nil
    }

    /// Adaptive polling: 15s base, backs off to 30s after 120s without interaction.
    /// Conforming types must provide `knownURIs` as an associated storage or
    /// implement their own `checkForNewPosts` logic.
    ///
    /// Default implementation uses a polling task with adaptive back-off.
    /// Override `checkForNewPosts` to provide the data-source-specific fetch.
    func startPolling(
        account _: AppAccount,
        appPassword _: String,
        using _: LiveBlueskyClient,
        interval _: TimeInterval = 15
    ) {
        // Default no-op; conforming types with polling support override this.
        // The full implementation lives in FeedTimelineViewModel and will be
        // extracted into a reusable form in a future phase.
    }

    func stopPolling() {
        // Default no-op.
    }

    func userDidInteract() {
        // Default no-op.
    }
}
