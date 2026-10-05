import SwiftUI

// MARK: - Reorder Support (iOS 27)

/// A reorder gesture expressed without the iOS 27 types, so call sites stay compilable against
/// the iOS 17 deployment target: which item ids moved, and where they should land.
struct ReorderRequest<ID: Hashable & Sendable>: Sendable {
    enum Destination: Sendable {
        case before(ID)
        case end
    }

    let sources: [ID]
    let destination: Destination
}

extension View {
    /// Marks a container as the reorder scope on iOS 27 and reports the resulting difference.
    ///
    /// No-op before iOS 27, where the same lists reorder through `onMove` in edit mode — so a
    /// call site pairs this with `.onMove` and one shared apply function.
    @ViewBuilder
    func appReorderContainer<Item: Identifiable>(
        for _: Item.Type,
        onChange: @escaping (ReorderRequest<Item.ID>) -> Void
    ) -> some View where Item.ID: Hashable & Sendable {
        if #available(iOS 27.0, *) {
            reorderContainer(for: Item.self) { difference in
                let destination: ReorderRequest<Item.ID>.Destination = switch difference.destination.position {
                case let .before(id):
                    .before(id)
                case .end:
                    .end
                }
                onChange(ReorderRequest(sources: difference.sources, destination: destination))
            }
        } else {
            self
        }
    }
}

extension DynamicViewContent {
    // NOTE: no `reorderableIfAvailable()` helper here on purpose. A `@ViewBuilder`
    // `if #available(iOS 27, *) { reorderable() } else { self }` is not expressible: the branches
    // produce `_ConditionalContent`, which does not conform to `DynamicViewContent`. Call sites
    // that want the iOS 27 drag affordance therefore branch on availability around the whole
    // `ForEach` (duplicating only the two modifiers, not the row builder) — see `AccountTabView`.
}
