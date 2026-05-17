import Foundation

@MainActor
final class ListDiffController {
    func compare(
        currentMembers: [BlueskyListMember],
        otherList: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> ListComparisonReport {
        let otherMembers = try await client.fetchListMembers(
            list: otherList,
            account: account,
            appPassword: appPassword
        )
        let currentByDID = Dictionary(uniqueKeysWithValues: currentMembers.map { ($0.actor.did, $0) })
        let otherByDID = Dictionary(uniqueKeysWithValues: otherMembers.map { ($0.actor.did, $0) })

        let overlap = currentByDID.keys
            .filter { otherByDID[$0] != nil }
            .compactMap { currentByDID[$0] }
            .sorted { $0.actor.handle.localizedCaseInsensitiveCompare($1.actor.handle) == .orderedAscending }

        let onlyInCurrent = currentByDID.keys
            .filter { otherByDID[$0] == nil }
            .compactMap { currentByDID[$0] }
            .sorted { $0.actor.handle.localizedCaseInsensitiveCompare($1.actor.handle) == .orderedAscending }

        let onlyInOther = otherByDID.keys
            .filter { currentByDID[$0] == nil }
            .compactMap { otherByDID[$0] }
            .sorted { $0.actor.handle.localizedCaseInsensitiveCompare($1.actor.handle) == .orderedAscending }

        return ListComparisonReport(
            otherList: otherList,
            overlap: overlap,
            onlyInCurrent: onlyInCurrent,
            onlyInOther: onlyInOther
        )
    }

    nonisolated func comparisonMembers(for bucket: ComparisonBucket, in report: ListComparisonReport) -> [BlueskyListMember] {
        switch bucket {
        case .overlap:
            return report.overlap
        case .onlyInCurrent:
            return report.onlyInCurrent
        case .onlyInOther:
            return report.onlyInOther
        }
    }

    nonisolated func selectedComparisonMembers(
        selectedDIDs: Set<String>,
        in report: ListComparisonReport
    ) -> [BlueskyListMember] {
        let all = report.overlap + report.onlyInCurrent + report.onlyInOther
        let filtered = all.filter { selectedDIDs.contains($0.actor.did) }

        return filtered.sorted {
            $0.actor.handle.localizedCaseInsensitiveCompare($1.actor.handle) == .orderedAscending
        }
    }

    nonisolated func selectComparisonBucket(_ bucket: ComparisonBucket, in report: ListComparisonReport) -> Set<String> {
        Set(comparisonMembers(for: bucket, in: report).map { $0.actor.did })
    }

    nonisolated func exportDiffRows(from report: ListComparisonReport) -> [String] {
        let sections: [(ComparisonBucket, [BlueskyListMember])] = [
            (.overlap, report.overlap),
            (.onlyInCurrent, report.onlyInCurrent),
            (.onlyInOther, report.onlyInOther),
        ]

        return sections.flatMap { bucket, members in
            members.map { member in
                [
                    bucket.title.csvField,
                    member.actor.handle.csvField,
                    member.actor.did.csvField,
                    (member.actor.displayName ?? "").csvField,
                ].joined(separator: ",")
            }
        }
    }
}
