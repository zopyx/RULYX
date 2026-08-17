import Foundation

// MARK: - Bluesky URL Constants

extension URL {
    /// The default Bluesky PDS endpoint.
    static let bskySocial: URL = {
        guard let url = URL(string: "https://bsky.social") else {
            preconditionFailure("Invalid URL: https://bsky.social")
        }
        return url
    }()
}
