import Foundation

/// Searches for Bluesky profiles and inspects them with full moderation context.
///
/// Supports two modes:
/// - **Inspect**: Looks up a single handle/DID and returns a full `ProfileInspection`.
/// - **Search**: Type-ahead actor search with client-side filtering and stale-query cancellation.
@MainActor
final class ProfileInspectorViewModel: ObservableObject {
    // MARK: - Properties

    /// The user's query text (handle, DID, or name fragment).
    @Published var query = ""
    /// Type-ahead search results (actors matching the query).
    @Published private(set) var searchResults: [BlueskyActor] = []
    /// Full profile inspection result after an `inspect` call.
    @Published private(set) var inspection: ProfileInspection?
    /// True while a profile inspection is loading.
    @Published private(set) var isLoading = false
    /// True while a type-ahead search is in progress.
    @Published private(set) var isSearching = false
    /// User-facing error message.
    @Published var errorMessage: String?

    /// The current search token used to discard stale responses.
    private var searchToken: SearchToken?

    // MARK: - Public Methods

    /// Inspects a profile by handle or DID with full moderation context (viewer state, list memberships, etc.).
    func inspect(
        account: AppAccount?,
        appPassword: String?,
        using client: BlueskyProfileInspecting
    ) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a Bluesky handle or DID."
            return
        }
        guard let account else {
            errorMessage = "Select an active account first."
            return
        }
        guard let appPassword, !appPassword.isEmpty else {
            errorMessage = BlueskyAPIError.missingCredentials.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        searchResults = []

        do {
            inspection = try await client.inspectProfile(
                query: trimmed,
                account: account,
                appPassword: appPassword
            )
        } catch {
            inspection = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Type-ahead actor search with stale-query cancellation.
    /// Only searches if the query is >= 2 characters.
    func search(
        account: AppAccount?,
        appPassword: String?,
        using client: BlueskyProfileInspecting
    ) async {
        let requestQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requestQuery.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        guard let account else {
            searchResults = []
            return
        }

        guard let appPassword, !appPassword.isEmpty else {
            searchResults = []
            return
        }

        let token = SearchToken()
        searchToken = token

        isSearching = true
        errorMessage = nil
        AppLogger.search.debug("Starting profile search for query '\(requestQuery, privacy: .public)'.")

        do {
            let actors = try await client.searchActors(
                query: requestQuery,
                account: account,
                appPassword: appPassword
            )

            guard searchToken?.matches(token) == true else {
                isSearching = false
                return
            }

            // Client-side filter: only include actors matching handle, displayName, or DID
            let lowered = requestQuery.lowercased()
            searchResults = actors.filter {
                $0.handle.lowercased().contains(lowered) ||
                    ($0.displayName?.lowercased().contains(lowered) ?? false) ||
                    $0.did.lowercased().contains(lowered)
            }
            // swiftformat:disable:next redundantSelf
            AppLogger.search.debug("Profile search for '\(requestQuery, privacy: .public)' returned \(self.searchResults.count) filtered results.")
        } catch {
            if AppError.isCancellation(error) {
                AppLogger.search.debug("Profile search for '\(requestQuery, privacy: .public)' was cancelled.")
                isSearching = false
                return
            }

            guard searchToken?.matches(token) == true else {
                isSearching = false
                return
            }

            let appError = AppError.from(error)
            AppLogger.search.error("Profile search for '\(requestQuery, privacy: .public)' failed: \(appError.message, privacy: .public)")
            errorMessage = appError.message
            searchResults = []
        }

        if searchToken?.matches(token) == true {
            isSearching = false
        }
    }

    /// Inspects a profile given a selected actor, setting the query to their handle.
    func inspect(
        actor: BlueskyActor,
        account: AppAccount?,
        appPassword: String?,
        using client: BlueskyProfileInspecting
    ) async {
        query = actor.handle
        await inspect(query: actor.did, account: account, appPassword: appPassword, using: client)
    }

    // MARK: - Private Methods

    /// Internal inspect-by-DID used by the public `inspect(actor:)` variant.
    private func inspect(
        query: String,
        account: AppAccount?,
        appPassword: String?,
        using client: BlueskyProfileInspecting
    ) async {
        guard let account else {
            errorMessage = "Select an active account first."
            return
        }
        guard let appPassword, !appPassword.isEmpty else {
            errorMessage = BlueskyAPIError.missingCredentials.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        searchResults = []

        do {
            inspection = try await client.inspectProfile(
                query: query,
                account: account,
                appPassword: appPassword
            )
        } catch {
            if AppError.isCancellation(error) {
                isLoading = false
                return
            }

            inspection = nil
            errorMessage = AppError.userMessage(from: error)
        }

        isLoading = false
    }
}
