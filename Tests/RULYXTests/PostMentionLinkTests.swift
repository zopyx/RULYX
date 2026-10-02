@testable import RULYX
import XCTest

/// Mentions in post text must be **tappable** and must carry the right target.
///
/// Regression: mention links used to be built as `mention://<did>`, which `URL(string:)`
/// rejects (the colon reads as a port separator), so a facet-rendered mention got `nil` as its
/// link — it looked like a link (blue, underlined) but tapping it did nothing.
final class PostMentionLinkTests: XCTestCase {
    // MARK: - MentionLink

    /// The core defect: a DID must survive the round trip through the link URL.
    func testMentionLinkCarriesADID() {
        let did = "did:plc:hnkokdnuim34g6xfkadpjvk4"
        let url = MentionLink.url(for: did)

        XCTAssertNotNil(url, "a DID must produce a valid URL — this is what used to fail")
        XCTAssertEqual(url.flatMap(MentionLink.target(from:)), did)
    }

    /// Handles (regex fallback, chat) keep working.
    func testMentionLinkCarriesAHandle() {
        let url = MentionLink.url(for: "someone.bsky.social")

        XCTAssertNotNil(url)
        XCTAssertEqual(url.flatMap(MentionLink.target(from:)), "someone.bsky.social")
    }

    func testMentionTargetIgnoresOtherSchemes() throws {
        XCTAssertNil(try MentionLink.target(from: XCTUnwrap(URL(string: "https://bsky.app"))))
    }

    /// Attributed strings built by older builds (target in the host) still resolve.
    func testMentionTargetStillReadsHostFormLinks() throws {
        XCTAssertEqual(try MentionLink.target(from: XCTUnwrap(URL(string: "mention://someone.bsky.social"))), "someone.bsky.social")
    }

    // MARK: - Facet rendering

    @MainActor func testFacetMentionBecomesTappableLinkCarryingTheDID() throws {
        let text = "@alice.bsky.social hi"
        let did = "did:plc:alice"
        // Byte range as the AppView reports it: exactly the mention, excluding the space.
        let facets = [
            RichFacet(
                index: RichFacetByteRange(byteStart: 0, byteEnd: 18),
                features: [RichFacetFeature(did: did)]
            ),
        ]

        let attributed = postAttributedString(from: text, facets: facets)

        let links = links(in: attributed)
        XCTAssertEqual(links.count, 1, "the mention must be a link")
        let mention = try XCTUnwrap(links.first)
        XCTAssertEqual(mention.text, "@alice.bsky.social")
        XCTAssertEqual(MentionLink.target(from: mention.url), did)
    }

    @MainActor func testFacetLinkFeatureBecomesItsURL() {
        let text = "read https://example.com now"
        let facets = [
            RichFacet(
                index: RichFacetByteRange(byteStart: 5, byteEnd: 24),
                features: [RichFacetFeature(uri: "https://example.com")]
            ),
        ]

        let links = links(in: postAttributedString(from: text, facets: facets))

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url.absoluteString, "https://example.com")
    }

    /// `#tag` and unknown features carry neither `did` nor `uri` and must stay plain text.
    @MainActor func testFacetWithoutTargetProducesNoLink() {
        let text = "#tag and more"
        let facets = [
            RichFacet(
                index: RichFacetByteRange(byteStart: 0, byteEnd: 4),
                features: [RichFacetFeature()]
            ),
        ]

        XCTAssertTrue(links(in: postAttributedString(from: text, facets: facets)).isEmpty)
    }

    /// A facet whose byte range lies outside the text must be skipped, not crash or mis-slice.
    @MainActor func testOutOfRangeFacetIsSkipped() {
        let text = "short @alice.bsky.social"
        let facets = [
            RichFacet(
                index: RichFacetByteRange(byteStart: 6, byteEnd: 400),
                features: [RichFacetFeature(did: "did:plc:alice")]
            ),
        ]

        let attributed = postAttributedString(from: text, facets: facets)

        XCTAssertEqual(String(attributed.characters), text, "the text is untouched")
    }

    // MARK: - Regex fallback

    @MainActor func testRegexFallbackMentionCarriesTheHandle() throws {
        let attributed = postAttributedString(from: "ping @bob.bsky.social please")

        let links = links(in: attributed)
        XCTAssertEqual(links.count, 1)
        let mention = try XCTUnwrap(links.first)
        XCTAssertEqual(MentionLink.target(from: mention.url), "bob.bsky.social")
    }

    // MARK: - Helpers

    /// Every link run of the attributed string, as (visible text, URL).
    private func links(in attributed: AttributedString) -> [(text: String, url: URL)] {
        attributed.runs.compactMap { run in
            guard let url = run.link else { return nil }
            return (String(attributed[run.range].characters), url)
        }
    }
}
