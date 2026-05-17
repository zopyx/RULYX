import Foundation

enum BlueskyAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case missingCredentials
    case sslPinFailure
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Bluesky endpoint URL is invalid."
        case .invalidResponse:
            "Bluesky returned an unexpected response."
        case .unauthorized:
            "Bluesky rejected the credentials. Check the handle and app password."
        case .missingCredentials:
            "No saved app password was found for this account."
        case .sslPinFailure:
            "The server certificate does not match the pinned fingerprint."
        case let .server(message):
            "Bluesky returned an error: \(message)"
        }
    }
}

struct APIErrorPayload: Decodable {
    let error: String?
    let message: String?
}
