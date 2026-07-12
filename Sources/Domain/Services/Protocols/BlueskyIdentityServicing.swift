import Foundation

/// DID resolution, PLC audit, and batch profile operations.
@MainActor
protocol BlueskyIdentityServicing: Sendable {
    /// Fetch the PLC audit log for a DID.
    func fetchPLCAuditLog(did: String) async throws -> [PLCAuditLogEntry]

    /// Batch-resolve a set of identifiers into profiles.
    func fetchProfileBatch(identifiers: [String]) async throws -> [BlueskyActor]
}
