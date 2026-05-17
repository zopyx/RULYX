import Foundation

@MainActor
final class BlueskyListService: ObservableObject, BlueskyListServicing {
    private let requestExecutor: BlueskyRequestExecuting
    private let sessionService: BlueskySessionServicing

    init(requestExecutor: BlueskyRequestExecuting, sessionService: BlueskySessionServicing) {
        self.requestExecutor = requestExecutor
        self.sessionService = sessionService
    }

    func fetchLists(for account: AppAccount, appPassword: String?) async throws -> [BlueskyList] {
        let response: GetListsResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            try await requestExecutor.send(
                path: "app.bsky.graph.getLists",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "actor", value: authSession.did),
                    URLQueryItem(name: "limit", value: "100"),
                ],
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return response.lists.map { item in
            BlueskyList(
                id: item.uri,
                name: item.name,
                description: item.description ?? item.purpose.displayTitle,
                memberCount: item.listItemCount,
                kind: item.purpose.kind
            )
        }
    }

    func fetchList(
        uri: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskyList? {
        let lists = try await fetchLists(for: account, appPassword: appPassword)
        return lists.first { $0.id == uri }
    }

    func fetchListMembers(
        list: BlueskyList,
        account: AppAccount,
        appPassword: String?
    ) async throws -> [BlueskyListMember] {
        var allMembers: [BlueskyListMember] = []
        var cursor: String?

        repeat {
            let page = try await fetchListMembersPage(
                list: list,
                cursor: cursor,
                account: account,
                appPassword: appPassword
            )
            allMembers.append(contentsOf: page.members)
            cursor = page.cursor
        } while cursor != nil

        return allMembers
    }

    func fetchListMembersPage(
        list: BlueskyList,
        cursor: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> PagedListMembers {
        let response: GetListResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            var queryItems = [
                URLQueryItem(name: "list", value: list.id),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }

            return try await requestExecutor.send(
                path: "app.bsky.graph.getList",
                method: "GET",
                queryItems: queryItems,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return PagedListMembers(
            members: response.items.map {
                BlueskyListMember(
                    recordURI: $0.uri,
                    actor: BlueskyActor(
                        did: $0.subject.did,
                        handle: $0.subject.handle,
                        displayName: $0.subject.displayName,
                        avatarURL: URL(string: $0.subject.avatar ?? "")
                    ),
                    createdAt: parseDate($0.createdAt)
                )
            },
            cursor: response.cursor
        )
    }

    func addActor(
        did actorDID: String,
        to list: BlueskyList,
        account: AppAccount,
        appPassword: String?
    ) async throws -> String {
        let response: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.listitem",
                record: ListItemRecord(
                    createdAt: ISO8601DateFormatter().string(from: .now),
                    list: list.id,
                    subject: actorDID
                )
            )

            let response: CreateRecordResponse = try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )

            return response
        }
        return response.uri
    }

    func removeMember(
        recordURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let record = try parseATURI(recordURI)
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = DeleteRecordRequest(
                repo: authSession.did,
                collection: record.collection,
                rkey: record.rkey
            )

            return try await requestExecutor.send(
                path: "com.atproto.repo.deleteRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    func createList(
        name: String,
        description: String,
        kind: BlueskyList.Kind,
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskyList {
        let response: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = CreateGenericRecordRequest(
                repo: authSession.did,
                collection: "app.bsky.graph.list",
                record: ListRecord(
                    type: "app.bsky.graph.list",
                    purpose: kind.purposeIdentifier,
                    name: name,
                    description: description.isEmpty ? nil : description,
                    createdAt: ISO8601DateFormatter().string(from: .now)
                )
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.createRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return BlueskyList(
            id: response.uri,
            name: name,
            description: description,
            memberCount: 0,
            kind: kind
        )
    }

    func deleteList(
        list: BlueskyList,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let record = try parseATURI(list.id)
        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = DeleteRecordRequest(
                repo: authSession.did,
                collection: record.collection,
                rkey: record.rkey
            )
            return try await requestExecutor.send(
                path: "com.atproto.repo.deleteRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }
    }

    func updateListMetadata(
        list: BlueskyList,
        title: String,
        description: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> BlueskyList {
        let record = try parseATURI(list.id)
        let _: CreateRecordResponse = try await sessionService.performAuthenticatedRequest(
            account: account,
            appPassword: appPassword
        ) { authSession in
            let body = PutRecordRequest(
                repo: authSession.did,
                collection: record.collection,
                rkey: record.rkey,
                record: ListRecord(
                    type: "app.bsky.graph.list",
                    purpose: list.kind.purposeIdentifier,
                    name: title,
                    description: description.isEmpty ? nil : description,
                    createdAt: ISO8601DateFormatter().string(from: .now)
                )
            )

            return try await requestExecutor.send(
                path: "com.atproto.repo.putRecord",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: authSession.accessJWT,
                hostURL: authSession.pdsURL
            )
        }

        return BlueskyList(
            id: list.id,
            name: title,
            description: description,
            memberCount: list.memberCount,
            kind: list.kind
        )
    }
}
