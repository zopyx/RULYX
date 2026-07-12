import Foundation
import Observation

/// Primary ViewModel for a single moderation list detail screen.
///
/// Manages member loading, search, bulk add/remove/block/mute/transfer, list comparison,
/// import preview, and metadata editing. Delegates to sub-controllers for specific concerns:
/// - `membersController`: Paginated member loading
/// - `batchController`: Batched actor operations with progress/cancellation
/// - `importController`: Parsing and previewing handle imports
/// - `diffController`: List comparison and diff report generation
@MainActor
final class ListDetailViewModel: ObservableObject {
    // MARK: - Properties

    /// All loaded members of the current list.
    var members: [BlueskyListMember] = []
    /// Members matching the current filter query.
    var filteredMembers: [BlueskyListMember] = []
    /// Actor search results for adding new members.
    var searchResults: [BlueskyActor] = []
    /// Lists available for comparison/transfer (excludes current list).
    var availableLists: [BlueskyList] = []
    /// Report from comparing two lists (current vs other).
    var comparisonReport: ListComparisonReport?
    /// Preview data for importing handles from raw text.
    var importPreview: ImportPreview?
    /// True while loading members.
    var isLoadingMembers = false
    /// True while loading more members.
    var isLoadingMoreMembers = false
    /// True when there are more member pages available.
    var hasMoreMembers = false
    /// True while loading the available-lists picker.
    var isLoadingAvailableLists = false
    /// True while searching for actors to add.
    var isSearching = false
    /// True while loading more search results.
    var isLoadingMoreSearchResults = false
    /// True when there are more search result pages.
    var hasMoreSearchResults = false
    /// True while generating a list comparison report.
    var isComparingLists = false
    /// True while preparing an import preview.
    var isPreparingImportPreview = false
    /// True while committing an import.
    var isImportingHandles = false
    /// True while updating list metadata.
    var isUpdatingMetadata = false
    /// Actors selected in the search results for bulk add.
    var selectedSearchActorIDs: Set<String> = []
    /// Members selected in the member list for bulk operations.
    var selectedMemberIDs: Set<String> = []
    /// Actor DIDs selected in the comparison report for bulk add.
    var selectedComparisonActorDIDs: Set<String> = []
    /// Result of the most recent bulk action (or nil).
    var bulkActionResult: ListBulkActionResult?
    /// General error message.
    var errorMessage: String?
    /// Error message specific to member loading.
    var membersErrorMessage: String?
    /// Error message specific to search.
    var searchErrorMessage: String?

    // MARK: - Sub-Controllers

    /// Tracks batch progress and cancellation state.
    let batchProgressState = ListBatchProgressState()
    /// Handles paginated member loading from the API.
    let membersController = ListMembersController()
    /// Cursor for paginating through search results.
    var searchCursor: String?
    /// The last search query, used for stale-response detection.
    var lastSearchQuery = ""
    /// Current client-side filter query for members.
    var currentMemberFilterQuery = ""
    /// Handles import preview generation.
    let importController = ListImportController()
    /// Handles list comparison and diff generation.
    let diffController = ListDiffController()
    /// Handles batch operations with progress and cancellation.
    let batchController = ListBatchController()
}
