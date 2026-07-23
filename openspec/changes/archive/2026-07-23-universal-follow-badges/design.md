## Context

Yesterday, follow-status badges ("Following" blue pill and "Follows me" green pill) with double-tap follow/unfollow were added to list detail views (`ListDetailMembersSection`, `iPadListDetailView`). The implementation uses `BlueskyListMember.viewerState` + optimistic state tracking with `pendingFollowActions`/`pendingUnfollowActions` sets.

Three other major member-list contexts still lack this functionality:
1. **RelationshipsView** — followers/following/blocking/blockedBy lists
2. **Search result lists** — UserSearchSheet, CustomSearchView users tab, ProfileInspectorView search results
3. **ListDetailComparisonSection** — comparison bucket member rows

The core challenge is that `BlueskyActor` (the common model used in these contexts) lacks `viewerState`, and the API response mappers discard the `viewer` field from the raw DTOs.

## Goals / Non-Goals

**Goals:**
- Add follow-status badges (Following/Follows me) to all member-list contexts
- Add double-tap follow/unfollow to all member-list contexts  
- Carry viewer state through `BlueskyActor` model from API responses
- Extract a shared badge component to avoid duplication
- Use the exact same optimistic-UI pattern as the existing list-detail implementation

**Non-Goals:**
- Changing the BlueskyProfileView (already has its own badge system)
- Adding badges to FollowerDiffView (uses simple labels, different UX)
- Extracting a shared double-tap modifier (each context has different gesture conflict patterns — keep per-context)
- Adding badges to Chat views (different interaction model)

## Decisions

### Decision 1: Add `viewerState` to `BlueskyActor` (optional)
**Approach:** Add an optional `viewerState: BlueskyViewerState?` field to `BlueskyActor`. Defaults to `nil`.
**Rationale:** The API already returns viewer state in all actor responses (followers, following, search). Currently it's discarded in the mapper. Carrying it through is the minimal-change approach vs. creating a new wrapper type.
**Alternatives considered:** Create `BlueskyActorWithViewer` struct — too much friction; Create parallel API that returns viewer state separately — extra network calls.

### Decision 2: Update API response mappers in `BlueskyProfileService`
**Approach:** Map `viewer` field from `ProfileViewBasic`/`ProfileViewDetailed` DTOs in `fetchFollowersPage`, `fetchFollowingPage`, `searchActorsPage`, and `searchActorsTypeahead` to populate `BlueskyActor.viewerState`.
**Rationale:** Single-point change in the service layer propagates to all consumers automatically.
**Risk:** DTOs may not always have viewer state. Handle gracefully (nil = no state).

### Decision 3: Extract `MemberFollowBadgesView` as shared component
**Approach:** Create a new file `MemberFollowBadgesView.swift` in `Sources/Shared/Components/` that wraps the badge rendering logic (identical to the existing `memberFollowBadges` in `ListDetailMembersSection`).
**Rationale:** The exact same badge rendering appears in 4+ contexts. Extraction prevents code duplication and ensures visual consistency.
**Interface:** `init(viewerState: BlueskyViewerState?, compact: Bool = false)` → renders the pill badges.

### Decision 4: Per-context double-tap implementation
**Approach:** Follow the existing pattern from list detail views — each view manages its own `pendingFollowActions`/`pendingUnfollowActions` sets, uses `effectiveViewerState()` to merge optimistic state with API state, and applies `TapGesture(count: 2)` or manual double-tap detection.
**Rationale:** Each context has different gesture conflict patterns (NavigationLinks, Buttons, swipe actions). A shared modifier would be overly complex.
**Pattern to copy:** The `ListDetailMembersSection.swift` implementation with `@State private var lastTapMemberID` and `@State private var lastTapTime` for reliable double-tap detection.

### Decision 5: Follow/unfollow via `BlueskySocialServicing`
**Approach:** Use the existing `container.social.followActor(did:account:appPassword:)` and `container.social.unfollowActor(recordURI:account:appPassword:)` methods.
**Rationale:** Already implemented, tested, and used in list detail views.

## Risks / Trade-offs

- **[Risk] API response doesn't include viewer state for some endpoints** → `viewerState` stays nil, badges don't show, no regression (graceful degradation)
- **[Risk] Viewer state staleness** → Badges reflect the state at fetch time. After a double-tap follow/unfollow, the optimistic update covers the gap until next refresh. This is acceptable and matches the existing pattern.
- **[Risk] Large relationships lists (10k+ followers)** → Loading viewer state for all is already part of the existing API response. No extra cost. But the double-tap on paginated lists could cause confusion if the actor isn't loaded yet. Mitigation: double-tap only works on loaded members.
- **[Trade-off] Reusing BlueskyActor instead of creating a dedicated type** → Simpler code, but viewerState is conceptually separate from core actor identity. Acceptable since viewerState is optional and defaults to nil.

## Migration Plan
1. Add `viewerState` to `BlueskyActor` (no existing callers depend on it — safe)
2. Update API mappers in `BlueskyProfileService`
3. Create shared `MemberFollowBadgesView` component
4. Update `RelationshipsView` (add badges + double-tap)
5. Update `UserSearchSheet` (add badges + double-tap)
6. Update `CustomSearchView` users tab (add badges + double-tap)
7. Update `ProfileInspectorView` search results (add badges)
8. Update `ListDetailComparisonSection` (add badges)
9. Build & verify compilation
10. Archive OpenSpec change

## Open Questions
- Do we need to add double-tap to `ProfileInspectorView` search results? These are compact search rows that already navigate to profile on tap — double-tap would conflict with navigation. Suggestion: badges only, no double-tap (navigate to profile to follow).
- Same question for `ListDetailComparisonSection` — rows use selection checkboxes. Suggestion: badges only, no double-tap.
