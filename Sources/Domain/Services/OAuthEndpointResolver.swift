import Foundation

/// Resolves OAuth 2.0 / OIDC endpoint URLs from a PDS's well-known metadata documents.
///
/// The AT Protocol OAuth flow requires two discovery steps:
/// 1. Fetch `/.well-known/oauth-protected-resource` from the PDS → get the Authorization Server URL
/// 2. Fetch `/.well-known/oauth-authorization-server` from the AS → get all OAuth endpoints
final class OAuthEndpointResolver {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - Protected Resource (PDS → AS URL)

    /// Fetches the OAuth-protected-resource metadata from a PDS URL
    /// to discover the Authorization Server URL.
    /// - Parameter pdsURL: The PDS base URL (e.g. `https://bsky.social`).
    /// - Returns: The resolved Authorization Server metadata.
    func resolveAuthorizationServer(pdsURL: URL) async throws -> OAuthAuthorizationServerMetadata {
        let resource = try await fetchProtectedResource(pdsURL: pdsURL)
        let asURL = resource.authorizationServers.first ?? pdsURL
        return try await fetchAuthorizationServerMetadata(asURL: asURL)
    }

    /// Fetch `/.well-known/oauth-protected-resource` from the PDS.
    private func fetchProtectedResource(pdsURL: URL) async throws -> OAuthProtectedResource {
        let url = pdsURL.appendingPathComponent(".well-known/oauth-protected-resource")
        let (data, response) = try await httpClient.data(from: url, source: "OAuth")
        guard (200 ..< 300).contains(response.statusCode) else {
            throw OAuthEndpointError.protectedResourceFetchFailed(response.statusCode)
        }
        return try JSONDecoder().decode(OAuthProtectedResource.self, from: data)
    }

    /// Fetch `/.well-known/oauth-authorization-server` from the AS.
    private func fetchAuthorizationServerMetadata(asURL: URL) async throws -> OAuthAuthorizationServerMetadata {
        let url = asURL.appendingPathComponent(".well-known/oauth-authorization-server")
        let (data, response) = try await httpClient.data(from: url, source: "OAuth")
        guard (200 ..< 300).contains(response.statusCode) else {
            throw OAuthEndpointError.asMetadataFetchFailed(response.statusCode)
        }
        return try JSONDecoder().decode(OAuthAuthorizationServerMetadata.self, from: data)
    }

    // MARK: - Direct Metadata Access

    /// Fetches the Authorization Server metadata from a known AS URL
    /// (useful when the AS URL is already known from a previous resolution).
    func fetchASMetadata(asURL: URL) async throws -> OAuthAuthorizationServerMetadata {
        try await fetchAuthorizationServerMetadata(asURL: asURL)
    }

    /// Fetches just the protected resource metadata from the PDS.
    func fetchProtectedResource(pdsURL: URL) async throws -> OAuthProtectedResource {
        try await fetchProtectedResource(pdsURL: pdsURL)
    }
}

// MARK: - Models

/// Response from `/.well-known/oauth-protected-resource` on the PDS.
struct OAuthProtectedResource: Decodable {
    /// The resolved Authorization Server URLs for this PDS.
    let authorizationServers: [URL]

    enum CodingKeys: String, CodingKey {
        case authorizationServers = "authorization_servers"
    }
}

/// Response from `/.well-known/oauth-authorization-server` on the AS.
struct OAuthAuthorizationServerMetadata: Decodable {
    /// The issuer URL of the Authorization Server.
    let issuer: URL
    /// The authorization endpoint URL.
    let authorizationEndpoint: URL
    /// The token endpoint URL.
    let tokenEndpoint: URL
    /// The pushed authorization request endpoint URL.
    let pushedAuthorizationRequestEndpoint: URL?
    /// The JWKS URI for public key discovery.
    let jwksURI: URL?
    /// The scopes supported by the AS.
    let scopesSupported: [String]?
    /// The response types supported.
    let responseTypesSupported: [String]?
    /// The grant types supported.
    let grantTypesSupported: [String]?
    /// The code challenge methods supported (for PKCE).
    let codeChallengeMethodsSupported: [String]?
    /// The token endpoint auth methods supported.
    let tokenEndpointAuthMethodsSupported: [String]?
    /// Whether DPoP is required.
    let dpopBoundAccessTokensSupported: Bool?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
        case jwksURI = "jwks_uri"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case dpopBoundAccessTokensSupported = "dpop_bound_access_tokens_supported"
    }
}

// MARK: - Errors

enum OAuthEndpointError: Error, LocalizedError {
    case protectedResourceFetchFailed(Int)
    case asMetadataFetchFailed(Int)
    case invalidAuthorizationServerURL

    var errorDescription: String? {
        switch self {
        case .protectedResourceFetchFailed(let code):
            "Failed to fetch OAuth protected resource metadata from PDS (HTTP \(code))."
        case .asMetadataFetchFailed(let code):
            "Failed to fetch OAuth authorization server metadata (HTTP \(code))."
        case .invalidAuthorizationServerURL:
            "The resolved Authorization Server URL is invalid."
        }
    }
}
