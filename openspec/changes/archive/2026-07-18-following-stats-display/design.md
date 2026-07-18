## Context

The "My Followings" view (`RelationshipsView` with `mode == .following`) currently shows a list of followed actors with avatar, display name, handle, and optionally a description. Stats (posts, followers, following) are only available by tapping into each profile or during CSV/JSON export via `LiveBlueskyClient.fetchProfileStats`.

## Goals / Non-Goals

**Goals:**
- Add a persisted "Show Stats" toggle in the toolbar menu (following mode only) — same pattern as existing "Show Descriptions"
- Render a stats row below each actor row when enabled (following mode only)
- Add a "No posts only" filter below the search field (following mode only) that filters to actors with zero posts
- Fetch stats via existing `LiveBlueskyClient.fetchProfileStats` after the following list loads
- Add minimal new localization keys (3 keys)

**Non-Goals:**
- Not modifying the `BlueskyActorRow` component — stats row is rendered in the parent `RelationshipsView`
- Not adding stats to other relationship modes (followers, blocking, blocked by)
- Not changing how the `BlueskyActor` model is serialized/cached

## Decisions

### Stats storage: @State dictionary vs model properties
- **Decision**: Store stats as `@State private var profileStats: [String: Stats]` alongside the actors array, rather than adding fields to `BlueskyActor`
- **Rationale**: Stats come from a separate batch API call (`app.bsky.actor.getProfiles`) that is orthogonal to the follow graph data. Adding them to `BlueskyActor` would require updating all init sites (previews, mocks, other fetch paths) and complicate serialization. A dictionary keyed by DID is simpler and doesn't affect existing model behavior.
- **Alternative considered**: Adding optional fields to `BlueskyActor` — rejected because it would require changes in preview/mock services and could bloat the cached data.

### Stats fetching: Automatic vs explicit trigger
- **Decision**: Fetch automatically after the following list loads
- **Rationale**: The export flow already calls `fetchProfileStats` with the same callback pattern. Making it automatic means stats are always available when the user toggles the view. The API is public (no auth needed) and batched in groups of 25.

### Filter access: search section vs separate section
- **Decision**: Place "No posts only" toggle below the search TextField in the existing search section, restricted to `.following` mode
- **Rationale**: It's a search/filter concern that affects which actors are visible. Placing it right below the search field keeps it contextually relevant. The search section is only shown when there are actors loaded, so it naturally avoids empty-state issues.

## Risks / Trade-offs

- **Large following lists** → For users following >1000 accounts, fetching stats could make 40+ API calls (25 per batch). Mitigation: fetchProfileStats already reports progress. The filter toggle is disabled until stats load.
- **Stats loading time** → The first time a user opens "My Followings" with a large list, stats will not be immediately available. Mitigation: stats load in background and UI updates reactively via `@State`. The stats row simply shows nothing until data arrives.
- **Cache invalidation** → Stats are fetched on every load/refresh of the following list. They are not cached in RelationshipCache (which only stores the actor list). This is acceptable since stats can change frequently.

## Migration Plan
No migration needed — new feature with no breaking changes to existing data or behavior.
