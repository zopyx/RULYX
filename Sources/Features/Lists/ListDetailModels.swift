import Foundation

// MARK: - ListBulkActionResult

/// Result of a bulk list operation, with succeeded actors and any failures.
struct ListBulkActionResult: Identifiable, Equatable {
    /// The type of bulk operation performed.
    enum Operation: Equatable {
        case add
        case remove
        case copy
        case move
        case `import`
        case block
        case mute
        case unblock
        case unmute
        case report

        /// User-facing title for the operation.
        var title: String {
            switch self {
            case .add:
                "Bulk Add"
            case .remove:
                "Bulk Remove"
            case .copy:
                "Copy Members"
            case .move:
                "Move Members"
            case .import:
                "Import Handles"
            case .block:
                "Block Followers"
            case .mute:
                "Mute Members"
            case .unblock:
                "Unblock Members"
            case .unmute:
                "Unmute Members"
            case .report:
                "Report Accounts"
            }
        }

        /// Past-tense verb for summary text (e.g. "added", "removed").
        var pastTenseVerb: String {
            switch self {
            case .add:
                "added"
            case .remove:
                "removed"
            case .copy:
                "copied"
            case .move:
                "moved"
            case .import:
                "imported"
            case .block:
                "blocked"
            case .mute:
                "muted"
            case .unblock:
                "unblocked"
            case .unmute:
                "unmuted"
            case .report:
                "reported"
            }
        }
    }

    /// A single failure with the actor and error message.
    struct Failure: Identifiable, Equatable {
        let actor: BlueskyActor
        let message: String

        var id: String {
            actor.id
        }
    }

    let operation: Operation
    let succeededActors: [BlueskyActor]
    let failures: [Failure]

    var id: String {
        "\(operation.title)-\(succeededActors.count)-\(failures.count)"
    }

    /// Human-readable summary of the operation result.
    var summaryText: String {
        let successCount = succeededActors.count
        let failureCount = failures.count

        if failureCount == 0 {
            return "\(successCount) account\(successCount == 1 ? "" : "s") \(operation.pastTenseVerb)."
        }

        if successCount == 0 {
            return "No accounts were \(operation.pastTenseVerb)."
        }

        return "\(successCount) account\(successCount == 1 ? "" : "s") \(operation.pastTenseVerb), \(failureCount) failed."
    }
}

// MARK: - ListComparisonReport

/// Results of comparing two lists: overlap, members only in each list.
struct ListComparisonReport: Equatable {
    let otherList: BlueskyList
    let overlap: [BlueskyListMember]
    let onlyInCurrent: [BlueskyListMember]
    let onlyInOther: [BlueskyListMember]
}

// MARK: - BatchProgress

/// Progress state for a batch operation, including completed/total counts.
struct BatchProgress: Equatable {
    let title: String
    let completedCount: Int
    let totalCount: Int
    let currentHandle: String?

    var fractionComplete: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

// MARK: - ImportPreviewItem

/// An individual entry in an import preview, classified by resolution status.
struct ImportPreviewItem: Identifiable, Hashable {
    /// Whether this token is ready, already present, a duplicate, or unresolvable.
    enum Classification: String {
        case ready
        case alreadyPresent
        case duplicate
        case unresolved

        var title: String {
            switch self {
            case .ready:
                "Ready to Import"
            case .alreadyPresent:
                "Already in List"
            case .duplicate:
                "Duplicate"
            case .unresolved:
                "Unresolved"
            }
        }
    }

    let token: String
    let actor: BlueskyActor?
    let classification: Classification
    let message: String?

    var id: String {
        let actorKey = actor?.did ?? token
        return "\(classification.rawValue)-\(actorKey)-\(token)"
    }

    /// The handle to display — falls back to the raw token if unresolved.
    var displayHandle: String {
        actor?.handle ?? token
    }
}

// MARK: - ImportPreview

/// Preview of an import operation, showing items grouped by classification.
struct ImportPreview: Equatable {
    let sourceDescription: String
    let items: [ImportPreviewItem]

    /// Items ready to be imported (resolved and not already present).
    var readyItems: [ImportPreviewItem] {
        items.filter { $0.classification == .ready }
    }

    /// Items that are already members of the target list.
    var alreadyPresentItems: [ImportPreviewItem] {
        items.filter { $0.classification == .alreadyPresent }
    }

    /// Items that are duplicates within the import payload.
    var duplicateItems: [ImportPreviewItem] {
        items.filter { $0.classification == .duplicate }
    }

    /// Items that could not be resolved to a known Bluesky account.
    var unresolvedItems: [ImportPreviewItem] {
        items.filter { $0.classification == .unresolved }
    }
}

// MARK: - ComparisonBucket

/// Categories for list comparison results.
enum ComparisonBucket: String, CaseIterable {
    case overlap
    case onlyInCurrent
    case onlyInOther

    var title: String {
        switch self {
        case .overlap:
            "Shared"
        case .onlyInCurrent:
            "Only Here"
        case .onlyInOther:
            "Only There"
        }
    }
}
