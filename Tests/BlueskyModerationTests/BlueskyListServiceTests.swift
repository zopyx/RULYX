@testable import BlueskyModeration
import XCTest

@MainActor
final class BlueskyListServiceTests: XCTestCase {
    private var requestExecutor: MockRequestExecutor!
    private var sessionService: MockSessionService!
    private var service: BlueskyListService!

    override func setUp() {
        super.setUp()
        requestExecutor = MockRequestExecutor()
        sessionService = MockSessionService()
        service = BlueskyListService(requestExecutor: requestExecutor, sessionService: sessionService)
    }

    func testFetchListsSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"lists": [
                {"uri": "at://list/1", "name": "Mod List", "purpose": "app.bsky.graph.defs#modlist", "listItemCount": 10},
                {"uri": "at://list/2", "name": "Curate List", "purpose": "app.bsky.graph.defs#curatelist", "listItemCount": 5}
            ]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(GetListsResponse.self, from: json)
        }

        let lists = try await service.fetchLists(for: makeAccount(), appPassword: "pass")
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists[0].kind, .moderation)
        XCTAssertEqual(lists[1].kind, .regular)
    }

    func testFetchListsNoCount() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"lists": [
                {"uri": "at://list/1", "name": "No Count", "purpose": "app.bsky.graph.defs#modlist"}
            ]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(GetListsResponse.self, from: json)
        }

        let lists = try await service.fetchLists(for: makeAccount(), appPassword: "pass")
        XCTAssertEqual(lists.count, 1)
        XCTAssertNil(lists[0].memberCount)
    }

    func testFetchListByURISuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"lists": [
                {"uri": "at://list/target", "name": "Target List", "purpose": "app.bsky.graph.defs#modlist"}
            ]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(GetListsResponse.self, from: json)
        }

        let list = try await service.fetchList(uri: "at://list/target", account: makeAccount(), appPassword: "pass")
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.name, "Target List")
    }

    func testFetchListByURINotFound() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"lists": [
                {"uri": "at://list/1", "name": "Other", "purpose": "app.bsky.graph.defs#modlist"}
            ]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(GetListsResponse.self, from: json)
        }

        let list = try await service.fetchList(uri: "at://list/nonexistent", account: makeAccount(), appPassword: "pass")
        XCTAssertNil(list)
    }

    func testFetchListMembersSuccess() async throws {
        var pageCount = 0
        sessionService.onAuthenticatedRequest = { _, _ in
            pageCount += 1
            let items = [["uri": "at://item/\(pageCount)", "subject": ["did": "did:plc:\(pageCount)", "handle": "u\(pageCount).bsky.social"]]]
            let json = pageCount <= 2
                ? try JSONSerialization.data(withJSONObject: ["cursor": "p\(pageCount)", "items": items])
                : try JSONSerialization.data(withJSONObject: ["items": items])
            return try JSONDecoder().decode(GetListResponse.self, from: json)
        }

        let members = try await service.fetchListMembers(list: makeList(), account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(members.count, 3)
    }

    func testAddActorSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"uri": "at://new/item", "cid": "cid123"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(CreateRecordResponse.self, from: json)
        }

        let result = try await service.addActor(did: "did:plc:new", to: makeList(), account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(result, "at://new/item")
    }

    func testRemoveMemberSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            EmptyResponse()
        }

        try await service.removeMember(recordURI: "at://did:plc:owner/app.bsky.graph.listitem/rkey123", account: makeAccount(), appPassword: "pass")
    }

    func testCreateListModeration() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"uri": "at://new/list", "cid": "cid123"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(CreateRecordResponse.self, from: json)
        }

        let list = try await service.createList(name: "New Mod List", description: "A test list", kind: .moderation, account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(list.name, "New Mod List")
        XCTAssertEqual(list.kind, .moderation)
        XCTAssertEqual(list.memberCount, 0)
    }

    func testCreateListRegular() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"uri": "at://new/list", "cid": "cid123"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(CreateRecordResponse.self, from: json)
        }

        let list = try await service.createList(name: "Curated", description: "", kind: .regular, account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(list.name, "Curated")
        XCTAssertEqual(list.kind, .regular)
        XCTAssertEqual(list.description, "Lists")
    }

    func testDeleteListSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            EmptyResponse()
        }

        try await service.deleteList(list: makeList(id: "at://did:plc:owner/app.bsky.graph.list/rkey123"), account: makeAccount(), appPassword: "pass")
    }

    func testUpdateListMetadataSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"uri": "at://list/updated", "cid": "cid456"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(CreateRecordResponse.self, from: json)
        }

        let updated = try await service.updateListMetadata(
            list: makeList(id: "at://did:plc:owner/app.bsky.graph.list/rkey123", name: "Old Name"),
            title: "New Name",
            description: "New description",
            account: makeAccount(),
            appPassword: "pass"
        )
        XCTAssertEqual(updated.name, "New Name")
        XCTAssertEqual(updated.description, "New description")
    }

    func testUpdateListMetadataEmptyDescription() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"uri": "at://list/updated", "cid": "cid456"}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(CreateRecordResponse.self, from: json)
        }

        let updated = try await service.updateListMetadata(
            list: makeList(id: "at://did:plc:owner/app.bsky.graph.list/rkey123", name: "Old", kind: .moderation),
            title: "New",
            description: "",
            account: makeAccount(),
            appPassword: "pass"
        )
        XCTAssertEqual(updated.name, "New")
        XCTAssertEqual(updated.description, "Moderation Lists")
    }

    func testFetchListMembersPageSuccess() async throws {
        sessionService.onAuthenticatedRequest = { _, _ in
            let json = """
            {"cursor": "next", "items": [{"uri": "at://item/1", "subject": {"did": "did:plc:1", "handle": "u1.bsky.social"}}]}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(GetListResponse.self, from: json)
        }

        let page = try await service.fetchListMembersPage(list: makeList(), cursor: nil, account: makeAccount(), appPassword: "pass")
        XCTAssertEqual(page.members.count, 1)
        XCTAssertEqual(page.cursor, "next")
    }
}
