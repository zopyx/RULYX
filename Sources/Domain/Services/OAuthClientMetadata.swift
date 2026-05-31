import Foundation

/// OAuth client metadata document as required by the AT Protocol OAuth spec.
///
/// This document must be hosted at a public HTTPS URL matching the `client_id`.
/// The Authorization Server fetches it dynamically during the authorization flow.
///
/// Reference: https://atproto.com/specs/oauth#client-metadata
///
/// For development, the spec allows `http://localhost/` as a client_id for local testing.
/// For production, this must be served from a stable HTTPS endpoint
/// (e.g. `https://rulyx.app/oauth-client-metadata.json`).
struct OAuthClientMetadata: Encodable {
    /// The client's identifier URL. Must match the URL where this JSON is hosted.
    let clientID: String
    /// The application type — `"native"` for iOS/mobile apps.
    let applicationType: String
    /// Allowed grant types.
    let grantTypes: [String]
    /// Space-separated scope string.
    let scope: String
    /// Allowed response types.
    let responseTypes: [String]
    /// Redirect URIs for the OAuth callback.
    let redirectURIs: [URL]
    /// Indicates DPoP-bound access tokens are required.
    let dpopBoundAccessTokens: Bool
    /// Token endpoint authentication method.
    let tokenEndpointAuthMethod: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case applicationType = "application_type"
        case grantTypes = "grant_types"
        case scope
        case responseTypes = "response_types"
        case redirectURIs = "redirect_uris"
        case dpopBoundAccessTokens = "dpop_bound_access_tokens"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    }

    /// Creates the standard client metadata for the RULYX iOS app.
    /// - Parameter clientID: The URL where this metadata JSON is hosted.
    static func standard(clientID: String) -> OAuthClientMetadata {
        OAuthClientMetadata(
            clientID: clientID,
            applicationType: "native",
            grantTypes: ["authorization_code", "refresh_token"],
            scope: "atproto transition:generic transition:chat.bsky",
            responseTypes: ["code"],
            redirectURIs: [URL(string: "com.ajung.rulyx:/oauth-callback")!],
            dpopBoundAccessTokens: true,
            tokenEndpointAuthMethod: "none"
        )
    }

    /// Returns the JSON representation for hosting.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Returns the JSON string for hosting.
    func jsonString() throws -> String {
        let data = try jsonData()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
