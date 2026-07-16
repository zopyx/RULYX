## Why

The RULYX app currently has two timeline implementations — `FeedTimelineView`/`FeedTimelineViewModel` (main timeline tab) and `ListTimelineView`/`ListTimelineViewModel` (list-scoped timeline) — that were built independently and diverged in architecture, state management, and UI patterns. This duplication creates maintenance burden, subtle behavioral differences for users, and makes adding timeline features (polling, inline threads, compose, AI classification) error-prone since each change must be applied twice. Unifying the timeline architecture eliminates ~700+ lines of duplicated code, enforces consistent behavior across all timeline surfaces, and simplifies future feature work.

## What Changes

- **Extract shared timeline view model protocol** (`TimelineViewModel`) defining common state (`TimelineState`), loading operations, optimistic interactions, inline thread expansion, and AI classification
- **Extract shared timeline UI components**: consolidate duplicated sheets (compose, reply, quote, image/video preview, likes, profile, share, delete confirmation) into reusable view modifiers or a `TimelineViewModifiers` component
- **Extract shared post row factory**: consolidate duplicated `postRowView`, context menu, swipe actions, and inline thread section into a `TimelinePostRow` component shared by both timelines
- **Unify state machine**: migrate `ListTimelineViewModel` from ad-hoc booleans (`isLoading`, `isLoadingMore`, `hasMore`, `errorMessage`) to the existing `TimelineState` enum
- **Normalize view model lifecycle**: standardize ownership (injected via `@State`) and initialization patterns across all timeline views
- **Add polling to ListTimelineView**: bring adaptive polling (with the same back-off strategy) to list timelines so users see new posts without manual refresh
- **Add feed picker to ListTimelineView**: allow switching between custom feeds when viewing list timelines
- **Unify new-post FAB**: extract the floating compose button into a shared `TimelineComposeFAB` component
- **Normalize navigation**: use `NavigationPath` + `TimelineRoute` consistently; remove `ListTimelineView`'s internal `NavigationStack` (caller manages navigation)
- **Consolidate AI classification trigger**: unify the `.task(id:)` trigger pattern across both views

## Capabilities

### New Capabilities

- `timeline-viewmodel-protocol`: Shared `TimelineViewModel` protocol defining the contract all timeline view models SHALL implement — state (`TimelineState`), entries, optimistic interactions, polling lifecycle, inline thread expansion, and AI classification
- `timeline-shared-components`: Extracted reusable SwiftUI views and modifiers for timeline-specific UI — compose FAB, sheet stack (compose, reply, quote, image/video, likes, profile, share, delete), post row with context menu/swipe actions/inline threads
- `list-timeline-polling`: Adaptive polling for list timelines matching the main feed's 15s–30s back-off strategy

### Modified Capabilities

- `timeline-polling-efficiency`: Extended to cover list timelines in addition to main feed
- `view-rendering-efficiency`: Consolidated post row rendering reduces view hierarchy duplication

## Impact

| Area | Files | Change |
|------|-------|--------|
| **View Models** | `FeedTimelineViewModel.swift`, `ListTimelineViewModel.swift` | Extract protocol, migrate `ListTimelineViewModel` to `TimelineState` |
| **Views** | `FeedTimelineView.swift` (~700L), `ListTimelineView.swift` (~650L) | Extract shared components, reduce both to ~300L thin wrappers |
| **New files** | `TimelineViewModel.swift` (protocol), `TimelinePostRow.swift`, `TimelineSheets.swift`, `TimelineComposeFAB.swift` | Reusable components |
| **iPad** | `iPadTimelineView.swift` | No structural change (already wraps `TimelineTab`) |
| **Navigation** | `TimelineTab.swift`, callers of `ListTimelineView` | Callers manage `NavigationStack`; `ListTimelineView` becomes embeddable |
| **Tests** | New test targets for shared components | Unit tests for protocol conformance, view model state transitions |
