import Foundation

// MARK: - PLC Directory

/// An entry in the PLC directory audit log for a DID.
struct PLCAuditLogEntry: Decodable {
    let did: String
    let operation: PLCOperation
    let cid: String?
    /// Whether this entry has been nullified by a later operation.
    let nullified: Bool?
    let createdAt: String
}

/// An operation recorded in the PLC audit log.
struct PLCOperation: Decodable {
    let type: String?
    /// Handles associated with this operation (e.g., `at://handle.bsky.social`).
    let alsoKnownAs: [String]?
    let services: [String: PLCServiceEntry]?
}

/// A service entry from the PLC directory.
struct PLCServiceEntry: Decodable {
    let type: String?
    let endpoint: String?
}

/// A handle change extracted from the PLC audit log for display in the UI.
struct HandleChange: Identifiable {
    let id: String
    let handle: String
    let date: Date
    let isCurrent: Bool
}

/// Processes a PLC audit log to extract unique handle changes over time.
/// Filters out nullified entries, deduplicates consecutive identical handles,
/// and marks the matching current handle.
func parseHandleChanges(from auditLog: [PLCAuditLogEntry], currentHandle: String) -> [HandleChange] {
    let entries = auditLog
        .filter { !($0.nullified ?? false) }
        .compactMap { entry -> (handle: String, date: Date)? in
            guard let alsoKnownAs = entry.operation.alsoKnownAs,
                  let atHandle = alsoKnownAs.first(where: { $0.hasPrefix("at://") }),
                  let date = parseDate(entry.createdAt)
            else {
                return nil
            }
            let handle = String(atHandle.dropFirst(5))
            return (handle, date)
        }
        .sorted { $0.date < $1.date }

    var seen = Set<String>()
    var result: [HandleChange] = []
    for (handle, date) in entries {
        if seen.insert(handle).inserted {
            result.append(HandleChange(
                id: "\(handle)-\(date.timeIntervalSince1970)",
                handle: handle,
                date: date,
                isCurrent: handle == currentHandle
            ))
        }
    }
    return result
}
