import Foundation

/// Provides CRUD operations for Bluesky moderation and reference lists.
/// Implementations handle API calls for fetching, creating, updating, deleting
/// lists, managing list members, and reporting lists via the AT Protocol.
@MainActor
protocol BlueskyListServicing {
    // MARK: - List Fetching

    /// Fetches all lists owned by the given account.
    /// - Parameters:
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: An array of `BlueskyList` objects owned by the account.
    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList]

    /// Fetches a single list by its AT URI.
    /// - Parameters:
    ///   - uri: The AT URI of the list to fetch.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: The `BlueskyList` if found, or `nil` if it doesn't exist.
    func fetchList(uri: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList?

    // MARK: - List Members

    /// Fetches all members of the specified list.
    /// - Parameters:
    ///   - list: The list whose members to fetch.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: An array of `BlueskyListMember` objects in the list.
    func fetchListMembers(list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> [BlueskyListMember]

    /// Fetches a paginated page of members for the specified list.
    /// - Parameters:
    ///   - list: The list whose members to fetch.
    ///   - cursor: An optional cursor string for fetching the next page.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: A `PagedListMembers` containing a page of members and an optional next cursor.
    func fetchListMembersPage(list: BlueskyList, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedListMembers

    /// Adds an actor to a list, returning the created record URI.
    /// - Parameters:
    ///   - actorDID: The DID of the actor to add to the list.
    ///   - list: The list to add the actor to.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: The AT URI of the newly created list membership record.
    func addActor(did actorDID: String, to list: BlueskyList, account: AppAccount, appPassword: String?) async throws -> String

    /// Removes a member from a list using their membership record URI.
    /// - Parameters:
    ///   - recordURI: The AT URI of the membership record to delete.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func removeMember(recordURI: String, account: AppAccount, appPassword: String?) async throws

    // MARK: - List CRUD

    /// Updates the title and description of an existing list.
    /// - Parameters:
    ///   - list: The list to update.
    ///   - title: The new title for the list.
    ///   - description: The new description for the list.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: The updated `BlueskyList` with the new metadata.
    func updateListMetadata(list: BlueskyList, title: String, description: String, account: AppAccount, appPassword: String?) async throws -> BlueskyList

    /// Creates a new list with the specified name, description, and kind.
    /// - Parameters:
    ///   - name: The name of the new list.
    ///   - description: The description of the new list.
    ///   - kind: The kind of list (e.g. moderation or reference).
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    /// - Returns: The newly created `BlueskyList`.
    func createList(name: String, description: String, kind: BlueskyList.Kind, account: AppAccount, appPassword: String?) async throws -> BlueskyList

    /// Deletes a list permanently.
    /// - Parameters:
    ///   - list: The list to delete.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func deleteList(list: BlueskyList, account: AppAccount, appPassword: String?) async throws

    // MARK: - Reporting

    /// Reports a list with an optional free-form reason.
    /// - Parameters:
    ///   - list: The list to report.
    ///   - reason: An optional human-readable explanation for the report.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func reportList(_ list: BlueskyList, reason: String?, account: AppAccount, appPassword: String?) async throws

    /// Reports a list with a typed moderation reason.
    /// - Parameters:
    ///   - list: The list to report.
    ///   - selectedReason: An optional `ModerationReportReasonType` specifying the report category.
    ///   - reason: An optional human-readable explanation for the report.
    ///   - account: The account to authenticate with.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func reportList(_ list: BlueskyList, selectedReason: ModerationReportReasonType?, reason: String?, account: AppAccount, appPassword: String?) async throws
}
