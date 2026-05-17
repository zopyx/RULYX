@testable import BlueskyModeration
import XCTest

final class BlueskyAPIDTOsTests: XCTestCase {
    func testGetListsResponseDecoding() throws {
        let json = """
        {"lists": [{"uri": "at://list/1", "name": "Test", "description": "Desc", "purpose": "app.bsky.graph.defs#modlist", "listItemCount": 5}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(GetListsResponse.self, from: json)
        XCTAssertEqual(result.lists.count, 1)
        XCTAssertEqual(result.lists[0].name, "Test")
        XCTAssertEqual(result.lists[0].purpose, .mod)
        XCTAssertEqual(result.lists[0].listItemCount, 5)
    }

    func testGetBlocksResponseDecoding() throws {
        let json = """
        {"cursor": "abc", "blocks": [{"did": "did:plc:blocked", "handle": "blocked.bsky.social", "displayName": "Blocked"}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(GetBlocksResponse.self, from: json)
        XCTAssertEqual(result.cursor, "abc")
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].did, "did:plc:blocked")
        XCTAssertEqual(result.blocks[0].displayName, "Blocked")
    }

    func testActorViewDecoding() throws {
        let json = """
        {"did": "did:plc:actor", "handle": "user.bsky.social", "displayName": "User", "avatar": "https://example.com/avatar.jpg", "createdAt": "2024-01-15T10:30:00Z"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ActorView.self, from: json)
        XCTAssertEqual(result.did, "did:plc:actor")
        XCTAssertEqual(result.handle, "user.bsky.social")
        XCTAssertEqual(result.displayName, "User")
        XCTAssertEqual(result.avatar, "https://example.com/avatar.jpg")
    }

    func testActorViewMinimalDecoding() throws {
        let json = """
        {"did": "did:plc:actor", "handle": "user.bsky.social"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ActorView.self, from: json)
        XCTAssertEqual(result.did, "did:plc:actor")
        XCTAssertNil(result.displayName)
        XCTAssertNil(result.avatar)
    }

    func testProfileViewDetailedDecoding() throws {
        let json = """
        {"did": "did:plc:profile", "handle": "profile.bsky.social", "displayName": "Profile", "description": "A test profile", "followersCount": 100, "followsCount": 50, "postsCount": 25}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ProfileViewDetailed.self, from: json)
        XCTAssertEqual(result.did, "did:plc:profile")
        XCTAssertEqual(result.followersCount, 100)
        XCTAssertEqual(result.followsCount, 50)
        XCTAssertEqual(result.postsCount, 25)
    }

    func testProfileViewerStateDecoding() throws {
        let json = """
        {"muted": true, "blockedBy": false, "blocking": "at://block/1", "following": "at://follow/1", "followedBy": "at://fby/1"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ProfileViewerState.self, from: json)
        XCTAssertTrue(result.muted ?? false)
        XCTAssertFalse(result.blockedBy ?? true)
        XCTAssertEqual(result.blocking, "at://block/1")
        XCTAssertEqual(result.following, "at://follow/1")
    }

    func testCreateSessionResponseDecoding() throws {
        let json = """
        {"did": "did:plc:test", "handle": "test.bsky.social", "accessJwt": "access-token", "refreshJwt": "refresh-token"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(CreateSessionResponse.self, from: json)
        XCTAssertEqual(result.did, "did:plc:test")
        XCTAssertEqual(result.accessJWT, "access-token")
        XCTAssertEqual(result.refreshJWT, "refresh-token")
    }

    func testCreateSessionResponseNoRefresh() throws {
        let json = """
        {"did": "did:plc:test", "handle": "test.bsky.social", "accessJwt": "access-token"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(CreateSessionResponse.self, from: json)
        XCTAssertEqual(result.accessJWT, "access-token")
        XCTAssertNil(result.refreshJWT)
    }

    func testListsWithMembershipResponseDecoding() throws {
        let jsonData = """
        {"listsWithMembership":[{"list":{"uri":"at://list/1","name":"Test List","purpose":"app.bsky.graph.defs#curatelist","listItemCount":10},"listItem":{"uri":"at://item/1","subject":{"did":"did:plc:sub","handle":"sub.bsky.social"}}}]}
        """
        let json = jsonData.data(using: .utf8)!
        let result = try JSONDecoder().decode(ListsWithMembershipResponse.self, from: json)
        XCTAssertEqual(result.listsWithMembership.count, 1)
        XCTAssertEqual(result.listsWithMembership[0].list.name, "Test List")
        XCTAssertNotNil(result.listsWithMembership[0].listItem)
    }

    func testGetFollowersResponseDecoding() throws {
        let json = """
        {"cursor": "next", "followers": [{"did": "did:plc:f1", "handle": "follower.bsky.social"}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(GetFollowersResponse.self, from: json)
        XCTAssertEqual(result.cursor, "next")
        XCTAssertEqual(result.followers.count, 1)
    }

    func testGetFollowsResponseDecoding() throws {
        let json = """
        {"follows": [{"did": "did:plc:fol", "handle": "follow.bsky.social"}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(GetFollowsResponse.self, from: json)
        XCTAssertNil(result.cursor)
        XCTAssertEqual(result.follows.count, 1)
    }

    func testListRecordEncoding() throws {
        let record = ListRecord(type: "app.bsky.graph.list", purpose: "app.bsky.graph.defs#modlist", name: "Test", description: "Desc", createdAt: "2024-01-01T00:00:00Z")
        let data = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["$type"] as? String, "app.bsky.graph.list")
        XCTAssertEqual(json["name"] as? String, "Test")
    }

    func testSubjectRecordEncoding() throws {
        let record = SubjectRecord(type: "app.bsky.graph.block", subject: "did:plc:target")
        let data = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["$type"] as? String, "app.bsky.graph.block")
        XCTAssertEqual(json["subject"] as? String, "did:plc:target")
    }

    func testParseATURI() throws {
        let components = try parseATURI("at://did:plc:owner/app.bsky.graph.listitem/rkey123")
        XCTAssertEqual(components.repo, "did:plc:owner")
        XCTAssertEqual(components.collection, "app.bsky.graph.listitem")
        XCTAssertEqual(components.rkey, "rkey123")
    }

    func testParseATURIInvalid() {
        XCTAssertThrowsError(try parseATURI("invalid-uri"))
    }

    func testParseATURIShortSegments() {
        XCTAssertThrowsError(try parseATURI("at://short"))
    }

    func testParseDateWithFractionalSeconds() {
        let date = parseDate("2024-01-15T10:30:00.123Z")
        XCTAssertNotNil(date)
    }

    func testParseDateWithoutFractionalSeconds() {
        let date = parseDate("2024-01-15T10:30:00Z")
        XCTAssertNotNil(date)
    }

    func testParseDateNil() {
        XCTAssertNil(parseDate(nil))
    }

    func testParseDateInvalid() {
        XCTAssertNil(parseDate("not-a-date"))
    }

    func testMapViewerStateNil() {
        XCTAssertNil(mapViewerState(nil))
    }

    func testMapViewerStateMapsCorrectly() {
        let viewer = ProfileViewerState(muted: true, blockedBy: false, blocking: "at://block/1", following: "at://follow/1", followedBy: "at://fby/1", mutedByList: nil, blockingByList: nil)
        let result = mapViewerState(viewer)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.muted ?? false)
        XCTAssertEqual(result?.blockingRecordURI, "at://block/1")
        XCTAssertTrue(result?.isBlocking ?? false)
        XCTAssertTrue(result?.isFollowing ?? false)
        XCTAssertTrue(result?.followsYou ?? false)
    }

    func testParseHandleChanges() {
        let entries = [
            PLCAuditLogEntry(did: "did:plc:test", operation: PLCOperation(type: "plc_operation", alsoKnownAs: ["at://old-handle.bsky.social"], services: nil), cid: nil, nullified: false, createdAt: "2024-01-01T00:00:00Z"),
            PLCAuditLogEntry(did: "did:plc:test", operation: PLCOperation(type: "plc_operation", alsoKnownAs: ["at://new-handle.bsky.social"], services: nil), cid: nil, nullified: false, createdAt: "2024-06-01T00:00:00Z"),
        ]
        let result = parseHandleChanges(from: entries, currentHandle: "new-handle.bsky.social")
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].isCurrent == false || result[1].isCurrent == true)
        XCTAssertEqual(result.first(where: { $0.isCurrent })?.handle, "new-handle.bsky.social")
    }

    func testParseHandleChangesFiltersNullified() {
        let entries = [
            PLCAuditLogEntry(did: "did:plc:test", operation: PLCOperation(type: "plc_operation", alsoKnownAs: ["at://old.bsky.social"], services: nil), cid: nil, nullified: true, createdAt: "2024-01-01T00:00:00Z"),
            PLCAuditLogEntry(did: "did:plc:test", operation: PLCOperation(type: "plc_operation", alsoKnownAs: ["at://current.bsky.social"], services: nil), cid: nil, nullified: false, createdAt: "2024-06-01T00:00:00Z"),
        ]
        let result = parseHandleChanges(from: entries, currentHandle: "current.bsky.social")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].handle, "current.bsky.social")
    }

    func testParseHandleChangesDeduplicates() {
        let entries = [
            PLCAuditLogEntry(did: "did:plc:test", operation: PLCOperation(type: "plc_operation", alsoKnownAs: ["at://same.bsky.social"], services: nil), cid: nil, nullified: false, createdAt: "2024-01-01T00:00:00Z"),
            PLCAuditLogEntry(did: "did:plc:test", operation: PLCOperation(type: "plc_operation", alsoKnownAs: ["at://same.bsky.social"], services: nil), cid: nil, nullified: false, createdAt: "2024-06-01T00:00:00Z"),
        ]
        let result = parseHandleChanges(from: entries, currentHandle: "same.bsky.social")
        XCTAssertEqual(result.count, 1)
    }

    func testListPurposeKindMapping() {
        XCTAssertEqual(ListPurpose.curate.kind, .regular)
        XCTAssertEqual(ListPurpose.mod.kind, .moderation)
    }

    func testListPurposeDisplayTitle() {
        XCTAssertEqual(ListPurpose.curate.displayTitle, "Curation list")
        XCTAssertEqual(ListPurpose.mod.displayTitle, "Moderation list")
    }

    func testDIDDocumentDecoding() throws {
        let json = """
        {"service": [{"id": "#atproto_pds", "type": "AtprotoPersonalDataServer", "serviceEndpoint": "https://pds.example.com"}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(DIDDocument.self, from: json)
        XCTAssertEqual(result.services.count, 1)
        XCTAssertEqual(result.services[0].id, "#atproto_pds")
        XCTAssertEqual(result.services[0].serviceEndpoint.absoluteString, "https://pds.example.com")
    }

    func testGetListResponseDecoding() throws {
        let json = """
        {"cursor": "next", "items": [{"uri": "at://item/1", "subject": {"did": "did:plc:sub", "handle": "sub.bsky.social"}}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(GetListResponse.self, from: json)
        XCTAssertEqual(result.cursor, "next")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].subject.did, "did:plc:sub")
    }

    func testStarterPacksWithMembershipDecoding() throws {
        let json = """
        {"starterPacksWithMembership": [{"starterPack": {"uri": "at://pack/1", "name": "Test Pack", "listItemCount": 5}, "listItem": null}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(StarterPacksWithMembershipResponse.self, from: json)
        XCTAssertEqual(result.starterPacksWithMembership.count, 1)
        XCTAssertNil(result.starterPacksWithMembership[0].listItem)
    }

    func testCreateRecordRequestEncoding() throws {
        let request = CreateRecordRequest(repo: "did:plc:repo", collection: "app.bsky.graph.listitem", record: ListItemRecord(createdAt: "now", list: "at://list/1", subject: "did:plc:sub"))
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["repo"] as? String, "did:plc:repo")
        XCTAssertEqual(json["collection"] as? String, "app.bsky.graph.listitem")
    }

    func testDeleteRecordRequestEncoding() throws {
        let request = DeleteRecordRequest(repo: "did:plc:repo", collection: "app.bsky.graph.listitem", rkey: "rkey123")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["rkey"] as? String, "rkey123")
    }

    func testActorReferenceRequestEncoding() throws {
        let request = ActorReferenceRequest(actor: "did:plc:target")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["actor"] as? String, "did:plc:target")
    }

    func testEmptyResponseDecoding() throws {
        let json = "{}".data(using: .utf8)!
        let result = try JSONDecoder().decode(EmptyResponse.self, from: json)
        XCTAssertNotNil(result)
    }

    func testAPIErrorPayloadDecoding() throws {
        let json = """
        {"error": "InvalidRequest", "message": "Bad request"}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(APIErrorPayload.self, from: json)
        XCTAssertEqual(result.error, "InvalidRequest")
        XCTAssertEqual(result.message, "Bad request")
    }

    func testPLCOperationDecoding() throws {
        let json = """
        {"type": "plc_operation", "alsoKnownAs": ["at://handle.bsky.social"], "services": {"atproto_pds": {"type": "AtprotoPersonalDataServer", "endpoint": "https://pds.example.com"}}}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(PLCOperation.self, from: json)
        XCTAssertEqual(result.type, "plc_operation")
        XCTAssertEqual(result.alsoKnownAs?.count, 1)
        XCTAssertEqual(result.services?.count, 1)
    }

    func testRichEmbedDecodesExternalView() throws {
        let json = """
        {
          "$type": "app.bsky.embed.external#view",
          "external": {
            "uri": "https://giphy.com/gifs/example",
            "title": "GIPHY Clip",
            "description": "Animated preview",
            "thumb": "https://cdn.example/thumb.jpg"
          }
        }
        """.data(using: .utf8)!

        let embed = try JSONDecoder().decode(RichEmbed.self, from: json)

        XCTAssertNil(embed.images)
        XCTAssertNil(embed.video)
        XCTAssertEqual(embed.external?.uri, "https://giphy.com/gifs/example")
        XCTAssertEqual(embed.external?.title, "GIPHY Clip")
        XCTAssertEqual(embed.external?.thumb, "https://cdn.example/thumb.jpg")
    }

    func testRichEmbedDecodesRecordWithMediaExternalView() throws {
        let json = """
        {
          "$type": "app.bsky.embed.recordWithMedia#view",
          "record": {
            "$type": "app.bsky.embed.record#view"
          },
          "media": {
            "$type": "app.bsky.embed.external#view",
            "external": {
              "uri": "https://giphy.com/gifs/example",
              "title": "Wrapped GIPHY Clip",
              "description": "Wrapped external media",
              "thumb": "https://cdn.example/wrapped-thumb.jpg"
            }
          }
        }
        """.data(using: .utf8)!

        let embed = try JSONDecoder().decode(RichEmbed.self, from: json)

        XCTAssertNil(embed.images)
        XCTAssertNil(embed.video)
        XCTAssertEqual(embed.external?.uri, "https://giphy.com/gifs/example")
        XCTAssertEqual(embed.external?.title, "Wrapped GIPHY Clip")
    }

    func testRichEmbedDecodesExternalViewWhenThumbIsObject() throws {
        let json = """
        {
          "$type": "app.bsky.embed.external#view",
          "external": {
            "uri": "https://giphy.com/gifs/example",
            "title": "GIPHY Clip",
            "description": "Animated preview",
            "thumb": {
              "$type": "blob",
              "ref": {
                "$link": "bafkreiabc123"
              },
              "mimeType": "image/jpeg",
              "size": 1024
            }
          }
        }
        """.data(using: .utf8)!

        let embed = try JSONDecoder().decode(RichEmbed.self, from: json)

        XCTAssertEqual(embed.external?.uri, "https://giphy.com/gifs/example")
        XCTAssertEqual(embed.external?.title, "GIPHY Clip")
        XCTAssertNil(embed.external?.thumb)
    }

    func testRichEmbedExternalRecognizesTenorAndProvidesInlineMediaURL() {
        let external = RichEmbedExternal(
            uri: "https://tenor.com/view/dance-cat-gif-12345",
            title: "Tenor",
            description: "Animated preview",
            thumb: "https://media.tenor.com/example.gif"
        )

        XCTAssertTrue(external.isTenorEmbed)
        XCTAssertEqual(external.preferredInlineMediaURL?.absoluteString, "https://media.tenor.com/example.gif")
    }
}
