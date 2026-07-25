import Foundation

/// Centralized URL string constants for all first-party and third-party
/// endpoints. URL extensions for Bluesky hosts are in `URL+Bluesky.swift`;
/// this enum provides the canonical string values for direct use and
/// documentation.
enum Endpoints {
    static let bskySocial = "https://bsky.social"
    static let euroskySocial = "https://eurosky.social"
    static let bskyAppViewServiceDID = "did:web:api.bsky.app#bsky_appview"
    static let publicAPIBSKY = "https://public.api.bsky.app"
    static let apiBSKYApp = "https://api.bsky.app"
    static let clearskyAPI = "https://api.clearsky.app"
    static let clearskyPublicAPI = "https://public.api.clearsky.services"
    static let plcDirectory = "https://plc.directory"
    static let huggingFaceBase = "https://huggingface.co"
    static let huggingFaceRaw = "https://huggingface.co/zopyx/rulyx-ai/resolve/main"
    static let gitHubRepo = "https://github.com/zopyx/RULYX"
    static let gitHubIssues = "https://github.com/zopyx/RULYX/issues"
    static let appWebsite = "https://rulyx.app"
    static let appPrivacy = "https://rulyx.app/privacy"
    static let appImprint = "https://rulyx.app/imprint"
    static let appLicense = "https://rulyx.app/license"
    static let appStoreLink = "https://apps.apple.com/app/rulyx/id1234567890"
}
