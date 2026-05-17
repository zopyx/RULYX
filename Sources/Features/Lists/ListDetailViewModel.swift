import Foundation

@MainActor
final class ListDetailViewModel: ObservableObject {
    @Published var members: [BlueskyListMember] = []
    @Published var filteredMembers: [BlueskyListMember] = []
    @Published var searchResults: [BlueskyActor] = []
    @Published var availableLists: [BlueskyList] = []
    @Published var comparisonReport: ListComparisonReport?
    @Published var importPreview: ImportPreview?
    @Published var isLoadingMembers = false
    @Published var isLoadingMoreMembers = false
    @Published var hasMoreMembers = false
    @Published var isLoadingAvailableLists = false
    @Published var isSearching = false
    @Published var isLoadingMoreSearchResults = false
    @Published var hasMoreSearchResults = false
    @Published var isComparingLists = false
    @Published var isPreparingImportPreview = false
    @Published var isImportingHandles = false
    @Published var isUpdatingMetadata = false
    @Published var selectedSearchActorIDs: Set<String> = []
    @Published var selectedMemberIDs: Set<String> = []
    @Published var selectedComparisonActorDIDs: Set<String> = []
    @Published var bulkActionResult: ListBulkActionResult?
    @Published var errorMessage: String?
    @Published var membersErrorMessage: String?
    @Published var searchErrorMessage: String?

    let batchProgressState = ListBatchProgressState()
    let membersController = ListMembersController()
    var searchCursor: String?
    var lastSearchQuery = ""
    var currentMemberFilterQuery = ""
    let importController = ListImportController()
    let diffController = ListDiffController()
    let batchController = ListBatchController()
}
