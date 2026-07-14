import Foundation

// MARK: - Clearsky

/// Top-level response from the ClearSky blocklist API.
struct ClearskyBlocklistResponse: Decodable {
    let data: ClearskyBlocklistData
}

struct ClearskyBlocklistData: Decodable {
    let blocklist: [ClearskyBlocklistEntry]?
}

/// Error response from the Clearsky API (e.g. AccountNotFound).
struct ClearskyAPIErrorResponse: Decodable {
    let errorType: String?
    let message: String?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
        case message
        case status
    }
}

/// A single entry in a ClearSky blocklist.
struct ClearskyBlocklistEntry: Codable, Sendable {
    let did: String
    /// ISO 8601 date string of when the block was created.
    let blockedDate: String

    enum CodingKeys: String, CodingKey {
        case did
        case blockedDate = "blocked_date"
    }
}

// MARK: - Clearsky Lists

/// Response from the ClearSky lists API (`/csky/api/v1/get-list/{handle}`).
struct ClearskyListsResponse: Decodable {
    let data: ClearskyListsData
}

struct ClearskyListsData: Decodable {
    let identifier: String
    let lists: [ClearskyListEntry]
}

/// A moderation list reported by ClearSky.
struct ClearskyListEntry: Decodable, Identifiable {
    let name: String
    let description: String?
    let did: String
    let url: String
    let createdDate: String
    let dateAdded: String

    var id: String {
        url
    }

    enum CodingKeys: String, CodingKey {
        case name, description, did, url
        case createdDate = "created_date"
        case dateAdded = "date_added"
    }
}

/// Response from the ClearSky total count endpoint.
struct ClearskyTotalResponse: Decodable {
    let data: ClearskyTotalData
}

struct ClearskyTotalData: Decodable {
    let count: Int
}
