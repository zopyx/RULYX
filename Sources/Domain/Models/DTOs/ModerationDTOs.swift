import Foundation

// MARK: - Moderation Report

/// Request body for `com.atproto.moderation.createReport`.
struct CreateModerationReportRequest: Encodable {
    let reasonType: String
    let reason: String?
    let subject: ModerationReportSubject
    /// Optional tool metadata identifying the reporting client.
    let modTool: ModerationReportTool?
}

/// The subject of a moderation report — either a repo (by DID) or a record (by URI + CID).
struct ModerationReportSubject: Encodable {
    let did: String?
    let uri: String?
    let cid: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let did, uri == nil {
            // Report a repo (actor) — use repoRef.
            try container.encode("com.atproto.admin.defs#repoRef", forKey: .type)
            try container.encode(did, forKey: .did)
        } else {
            // Report a specific record — use strongRef.
            try container.encode("com.atproto.repo.strongRef", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(cid, forKey: .cid)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case did
        case uri
        case cid
    }
}

/// Metadata about the tool used to submit a moderation report.
struct ModerationReportTool: Encodable {
    /// Name of the reporting tool (e.g., "RULYX/1.0").
    let name: String
    /// Optional key-value metadata associated with the report.
    let meta: [String: String]?
}

/// Response from `com.atproto.moderation.createReport`.
struct CreateModerationReportResponse: Decodable {
    let id: Int
    let reasonType: String
    let reason: String?
    let reportedBy: String
    let createdAt: String
}

/// Predefined reason types for moderation reports, matching AT Protocol lexicon.
enum ModerationReportReasonType: String, CaseIterable, Identifiable {
    case harassmentTargeted = "tools.ozone.report.defs#reasonHarassmentTargeted"
    case harassmentHateSpeech = "tools.ozone.report.defs#reasonHarassmentHateSpeech"
    case harassmentDoxxing = "tools.ozone.report.defs#reasonHarassmentDoxxing"
    case harassmentTroll = "tools.ozone.report.defs#reasonHarassmentTroll"
    case harassmentOther = "tools.ozone.report.defs#reasonHarassmentOther"

    var id: String {
        rawValue
    }

    /// The default reason used when no specific reason is chosen.
    static let simplifiedDefault = ModerationReportReasonType.harassmentOther
}
