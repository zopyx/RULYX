import Foundation

@MainActor
final class ProfileInspectorViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var searchResults: [BlueskyActor] = []
    @Published private(set) var inspection: ProfileInspection?
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private var searchToken: SearchToken?

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

    func inspect(
        actor: BlueskyActor,
        account: AppAccount?,
        appPassword: String?,
        using client: BlueskyProfileInspecting
    ) async {
        query = actor.handle
        await inspect(query: actor.did, account: account, appPassword: appPassword, using: client)
    }

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
