import Foundation

struct ListBulkActionResult: Identifiable, Equatable {
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
                "Block Members"
            case .mute:
                "Mute Members"
            case .unblock:
                "Unblock Members"
            case .unmute:
                "Unmute Members"
            }
        }

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
            }
        }
    }

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

struct ListComparisonReport: Equatable {
    let otherList: BlueskyList
    let overlap: [BlueskyListMember]
    let onlyInCurrent: [BlueskyListMember]
    let onlyInOther: [BlueskyListMember]
}

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

struct ImportPreviewItem: Identifiable, Hashable {
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

    var displayHandle: String {
        actor?.handle ?? token
    }
}

struct ImportPreview: Equatable {
    let sourceDescription: String
    let items: [ImportPreviewItem]

    var readyItems: [ImportPreviewItem] {
        items.filter { $0.classification == .ready }
    }

    var alreadyPresentItems: [ImportPreviewItem] {
        items.filter { $0.classification == .alreadyPresent }
    }

    var duplicateItems: [ImportPreviewItem] {
        items.filter { $0.classification == .duplicate }
    }

    var unresolvedItems: [ImportPreviewItem] {
        items.filter { $0.classification == .unresolved }
    }
}

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
