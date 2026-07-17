import Combine
import Foundation

/// Download-only observable state kept separate from the media grid so frequent
/// progress updates do not invalidate every thumbnail in the browser.
@MainActor
final class MediaDownloadProgressState: ObservableObject {
    @Published private(set) var completedItems = 0
    @Published private(set) var totalItems = 0
    @Published private(set) var fractionCompleted = 0.0
    @Published private(set) var detail: String?

    private var fractionsByIndex: [Int: Double] = [:]
    private var aggregateFraction = 0.0

    func start(total: Int) {
        completedItems = 0
        totalItems = total
        fractionCompleted = 0
        detail = nil
        fractionsByIndex.removeAll(keepingCapacity: true)
        aggregateFraction = 0
    }

    func update(_ progress: MediaAssetProgress) {
        update(
            index: progress.index,
            fraction: progress.fractionCompleted,
            detail: progress.filenameStem
        )
    }

    func complete(index: Int, completed: Int, detail: String?) {
        update(index: index, fraction: 1, detail: detail)
        completedItems = min(max(0, completed), totalItems)
    }

    private func update(index: Int, fraction: Double, detail: String?) {
        let clampedFraction = min(max(0, fraction), 1)
        let previousFraction = fractionsByIndex[index] ?? 0
        guard clampedFraction >= previousFraction else { return }

        fractionsByIndex[index] = clampedFraction
        aggregateFraction += clampedFraction - previousFraction
        fractionCompleted = totalItems > 0
            ? min(max(aggregateFraction / Double(totalItems), 0), 1)
            : 0
        if let detail, !detail.isEmpty {
            self.detail = detail
        }
    }
}
