@testable import RULYX
import XCTest

/// Tests for per-host certificate-pinning enforcement scope.
final class CertificatePinningTests: XCTestCase {
    func testFirstPartyHostsAreEnforced() {
        let enforced = [
            "bsky.social",
            "chat.bsky.social",
            "video.bsky.social",
            "api.bsky.app",
            "public.api.bsky.app",
            "api.clearsky.app",
            "public.api.clearsky.services",
            "plc.directory",
        ]
        for host in enforced {
            XCTAssertTrue(CertificatePinningDelegate.isEnforcedHost(host), "\(host) should be pinned")
        }
    }

    func testCustomPDSHostsAreNotEnforced() {
        let notEnforced = [
            "pds.example.com",
            "selfhosted.social",
            "example.com",
            "bsky.social.evil.example.com",
            "",
        ]
        for host in notEnforced {
            XCTAssertFalse(CertificatePinningDelegate.isEnforcedHost(host), "\(host) must not be pinned")
        }
    }

    func testLookalikeHostsDoNotMatchSuffix() {
        // Suffix matching requires a dot boundary — "evil-bsky.social" must not
        // be treated as a subdomain of "bsky.social".
        XCTAssertFalse(CertificatePinningDelegate.isEnforcedHost("evil-bsky.social"))
        XCTAssertFalse(CertificatePinningDelegate.isEnforcedHost("notbsky.app"))
        XCTAssertFalse(CertificatePinningDelegate.isEnforcedHost("fakeplc.directory.attacker.com"))
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertTrue(CertificatePinningDelegate.isEnforcedHost("API.BSKY.APP"))
        XCTAssertTrue(CertificatePinningDelegate.isEnforcedHost("Chat.Bsky.Social"))
    }
}
