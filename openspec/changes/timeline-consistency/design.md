## Context

RULYX has two timeline implementations that serve different data sources but render nearly identical UIs:

| Aspect | `FeedTimelineView` + `FeedTimelineViewModel` | `ListTimelineView` + `ListTimelineViewModel` |
|--------|---------------------------------------------|---------------------------------------------|
| **Source** | Following feed or custom feed URI | Bluesky list member posts (server list feed + fallback) |
| **Lines** | 701 (view) + 388 (VM) = 1089 | 652 (view) + 339 (VM) = 991 |
| **State** | `TimelineState` enum | Separate `isLoading`, `isLoadingMore`, `hasMore`, `errorMessage` |
| **Polling** | Yes (adaptive 15s–30s) | No |
| **Feed picker** | Yes | No |
| **Navigation** | Caller's `NavigationStack` + `NavigationPath` | Internal `NavigationStack` |
| **ViewModel** | Injected via `@State` | Created in `init()` via `@State` |
| **Post row** | `postRowView(entry:)` private method | `postRowView(entry:)` + `postRowCallbacks(entry:)` |
| **Sheets** | Inline `.sheet()`/`.fullScreenCover()` modifiers | Identical but duplicated |

The post row, context menu, swipe actions, and all 8+ sheet presentations are structurally identical across both views. Only the data source and a few feed-specific features (feed picker, polling banner, mute-word context action) differ.

## Goals / Non-Goals

**Goals:**
- Eliminate ~700 lines of duplicated UI code
- Enforce consistent state management via `TimelineState` across all timelines
- Enable polling for list timelines
- Make adding new timeline features a single-change operation
- Preserve all existing behavior and user-visible functionality

**Non-Goals:**
- Changing the data fetching backend or Bluesky API integration
- Adding new timeline types (e.g., hashtag, search) — this design enables them but doesn't implement
- Modifying `ThreadView` or the compose flow beyond what's needed for consistency
- iPad-specific timeline changes (iPadTimelineView already wraps TimelineTab)
- Performance optimization of the polling algorithm itself (already addressed by `timeline-polling-efficiency`)

## Decisions

### 1. Protocol over class hierarchy

**Decision**: Define `TimelineViewModel` as a Swift protocol with default implementations via extensions where possible.

**Alternatives considered**:
- **Base class with inheritance**: SwiftUI + `@Observable` doesn't play well with class hierarchies; stored property overrides conflict with macro expansion. Protocol + extension gives cleaner separation.
- **Generic view with type parameter**: Would work but adds complexity at call sites. Protocol erasure (`any TimelineViewModel`) keeps existing injection patterns simple.

**Rationale**: Both concrete VMs are already `@Observable @MainActor` final classes with nearly identical method signatures. A protocol codifies the contract without forcing either VM to change its internal data-fetching logic.

### 2. Shared components as standalone SwiftUI views

**Decision**: Extract `TimelinePostRow`, `TimelineComposeFAB`, and `TimelineSheets` as standalone structs in `Sources/Shared/Components/Timeline/`.

**Alternatives considered**:
- **ViewModifier chain**: Sheets as modifiers would work but become unwieldy with 8+ sheet types and their bindings. Standalone views with `@Binding` properties are clearer.
- **ViewBuilder functions in an extension**: Less testable, harder to preview. Standalone views can have their own `#Preview`.

**Rationale**: Each extracted component solves one concern and can be independently tested and previewed. The `TimelineSheets` component uses a single `@ViewBuilder` with all sheet modifiers applied sequentially — this is the standard SwiftUI pattern.

### 3. `ListTimelineView` loses its internal NavigationStack

**Decision**: Remove `NavigationStack` from `ListTimelineView`. The embedding view (e.g., `ListDetailView`) is responsible for wrapping it in a `NavigationStack` and binding a `NavigationPath`.

**Alternatives considered**:
- **Keep internal NavigationStack**: Would require `TimelineSheets` to handle both internal and external navigation differently, adding complexity.

**Rationale**: This matches the `FeedTimelineView` pattern (wrapped by `TimelineTab`'s `NavigationStack`). Callers that currently present `ListTimelineView` as a sheet or in a `NavigationSplitView` detail column already have a navigation context. Only standalone presentations need the caller to add a `NavigationStack` wrapper.

### 4. Polling extracted into protocol extension

**Decision**: Move the polling implementation (`startPolling`, `stopPolling`, `checkForNewPosts`, `userDidInteract`, the adaptive interval logic) into a `TimelineViewModel` protocol extension so both VMs inherit it without duplication.

**Rationale**: The polling code in `FeedTimelineViewModel` is ~60 lines and uses only `knownURIs`, `state`, and `newPostCount` — all of which will be protocol requirements. The only VM-specific part is `fetchFeed()` (which already dispatches to the right data source). This eliminates copy-paste.

### 5. `ListTimelineViewModel` migration strategy

**Decision**: Migrate `ListTimelineViewModel` in-place rather than rewriting it. Replace `isLoading`/`isLoadingMore`/`hasMore`/`errorMessage` with `state: TimelineState` and computed property accessors.

**Migration path**:
```
Before:                           After:
isLoading    → state == .initialLoading
isLoadingMore → state == .loadingMore
hasMore       → state.hasMore
errorMessage  → state.errorMessage
```

This is mechanical and low-risk. The existing `SourceMode` enum and fallback pagination logic remain unchanged.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| **Protocol requirement explosion**: Trying to put too much in the protocol makes it rigid. | Only extract methods that are genuinely shared. VM-specific internals (`SourceMode`, `memberCursors`, `fetchFeed`) stay private. |
| **`ListTimelineView` callers break**: Removing the internal `NavigationStack` may break existing callers. | Audit all call sites (`ListDetailView`, `InternalListDetailView`, `iPadListDetailView`, and any navigation destination that wraps it) before removing. Add a `NavigationStack` wrapper at each call site. |
| **Polling degrades list timeline performance**: Polling every 15s for a list with many members could hammer the API. | List polling uses the same adaptive back-off as feed polling. Additionally, list feeds tend to have fewer updates than following feeds, so the check is lightweight (limit=10). |
| **`ListTimelineViewModel.loadMore` fallback logic**: The existing fallback from server list feed to member author feeds is complex and uses `sourceMode`. | Keep the fallback logic internal to `ListTimelineViewModel`; it doesn't need to be part of the protocol. |
| **Regression in mute-word context menu**: Only `FeedTimelineView` currently has the "Mute word" context menu action. | Include it in `TimelinePostRow` so list timelines also get this feature. |

## Migration Plan

1. **Phase 1 — Extract protocol**: Define `TimelineViewModel` protocol in a new file. Add conformance to `FeedTimelineViewModel` (no behavioral changes). Verify build.
2. **Phase 2 — Extract shared components**: Create `TimelinePostRow`, `TimelineComposeFAB`, `TimelineSheets`. Wire `FeedTimelineView` to use them. Verify build + manual smoke test.
3. **Phase 3 — Migrate ListTimelineViewModel**: Replace boolean state with `TimelineState`. Add protocol conformance. Add polling support.
4. **Phase 4 — Wire ListTimelineView**: Replace duplicated code with shared components. Remove internal `NavigationStack`. Update callers.
5. **Phase 5 — Cleanup & validate**: Remove dead code from both views. Verify all existing functionality via manual testing across both feed and list timelines.

Each phase is independently buildable and testable.

## Open Questions

1. **Should `TimelinePostRow` own the `makeAuthorCallbacks` logic?** Currently `makeAuthorCallbacks` is duplicated in both view files. It could move into the shared component or stay as a helper in each view.
2. **Should `ListTimelineView` get the feed picker?** The proposal mentions it, but list timelines are scoped to list members — adding a custom feed on top might confuse users. Decision deferred to implementation.
3. **Protocol naming**: `TimelineViewModel` vs `TimelineViewModelProtocol` — Swift conventions favor the shorter form but `TimelineViewModel` already implies a concrete type. Use `TimelineViewModelProtocol` to be explicit.
