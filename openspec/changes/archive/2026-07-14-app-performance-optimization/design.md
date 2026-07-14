## Context

The RULYX iOS app is a SwiftUI-based Bluesky moderation tool with ~51K lines of Swift. Performance profiling and code review revealed several systemic bottlenecks:

1. **Avatar images never cache** — `FreshAvatarImage` uses an ephemeral `URLSession` with `reloadIgnoringLocalCacheData`, meaning every avatar fetch is a fresh network request. This is the #1 source of redundant network calls. Avatars are displayed in timeline posts, actor rows, profile views, and list rows.

2. **Image pipeline has no disk cache** — `ThumbnailPipeline` uses an in-memory `NSCache` only. Images are re-downloaded on every cold launch.

3. **Excessive view re-rendering** — Many `ObservableObject` view models use `@Published` properties that trigger full view body re-evaluations. The `BlueskyProfileView` is 1841 lines of SwiftUI — SwiftUI diffing is O(n) over the body tree.

4. **Timeline polling is always-on** — Polls every 8 seconds regardless of whether the timeline tab is visible. This burns battery and network bandwidth.

5. **No Equatable conformance on row data** — List rows lack identity optimization, causing SwiftUI to diff more aggressively than needed.

## Goals / Non-Goals

**Goals:**
- Reduce redundant avatar/thumbnail network fetches by 80%+ on re-visits
- Eliminate avatar re-fetching on tab switches
- Reduce timeline background network calls by ~90% by suspending polling when the timeline tab is hidden
- Improve scroll smoothness in large lists by reducing view body re-evaluation
- Zero behavior change — users see exactly the same data, only faster

**Non-Goals:**
- No data model changes, no API changes, no JSON schema changes
- No CoreData, no new third-party dependencies
- Not addressing network latency or server response times (those are upstream)
- Not addressing the GIF picker or media download service performance
- Not a full architectural rewrite — targeted changes only

## Decisions

### Decision 1: Consolidate avatar loading into ThumbnailPipeline

**Choice**: Replace `FreshAvatarImage`'s ephemeral URLSession with `ThumbnailPipeline`.

**Rationale**:
- `ThumbnailPipeline` already exists and provides in-memory caching via `NSCache` + ImageIO downsampling
- It's already used by `PostAuthorHeader` (timeline author avatars) via `ThumbnailImageView`
- `FreshAvatarImage` is used in `BlueskyActorRow` (used in ListsView, RelationshipsView, etc.)
- Adding disk caching to one pipeline is simpler than maintaining two

**Alternatives considered**:
- Add a separate disk cache layer to `FreshAvatarImage` — would duplicate caching logic
- Use `URLCache` with shared `URLSession` — less control over TTL and eviction
- Switch to `AsyncImage` — no caching control, no downsampling

**Implementation**:
- Add an on-disk cache layer to `ThumbnailPipeline` actor
- Change `FreshAvatarImage` to delegate to `ThumbnailPipeline` instead of its own URLSession
- Keep `AvatarSession` but redirect it through the pipeline
- Add disk cache TTL check (24h default)
- Respect `maxPixelSize` for memory-efficient storage

### Decision 2: File-system disk cache with LRU eviction

**Choice**: Use file system (caches directory) with a simple LRU tracking via access timestamps.

**Rationale**:
- No need for CoreData or SQLite for simple image blobs
- caches directory is eligible for OS cleanup under storage pressure
- File system reads are fast for cached images (typically <2ms for small avatars)
- URL-based naming avoids collisions: `cache_key_<md5_url>_<pixelSize>.data`
- LRU eviction via access-time file attribute (`NSFileAccessDateKey`)

**Staleness model**:
- Write TTL: 24 hours for avatars (they rarely change), 72 hours for thumbnails
- On read: check modification date. If stale → delete + re-fetch
- On write: overwrite if exists (no versioning needed)

### Decision 3: @Observable macro migration for key view models

**Choice**: Migrate `BlueskyProfileViewModel` and `ListsViewModel` from `ObservableObject` + `@Published` to `@Observable` macro.

**Rationale**:
- `@Observable` (iOS 17+) provides per-property observation — only views reading the specific changed property re-evaluate
- `@Published` causes SwiftUI to re-evaluate the entire view body reading the ObservableObject
- Both view models already target iOS 17+ (per project requirements)
- The `FeedTimelineViewModel` already uses `@Observable` — reuse the same pattern

**Risk**: `@Observable` properties must be accessed from the main actor. Both view models are already `@MainActor`. Low risk.

### Decision 4: Tab-visibility-based polling suspension

**Choice**: Move `startPolling` call from `FeedTimelineView.task` to only activate when view is visible, and cancel on disappear.

**Rationale**:
- Currently polling starts on `.task` (which fires on first appearance) and stops on `.onDisappear` (which fires on navigation away)
- But `.onDisappear` may not fire for TabView tab switches — need to check if TabView uses `.onDisappear` reliably
- Better approach: use `@Environment(\.scenePhase)` or pass visibility state from the tab
- Simplest correct approach: move polling lifecycle to `TimelineTab` which wraps the `FeedTimelineView` and has explicit tab lifecycle

**Implementation**:
- `TimelineTab` manages a `TimelineState` for visibility
- `FeedTimelineView` receives a binding `isVisible` from the tab
- Polling starts when `isVisible == true` and stops when `isVisible == false`
- Use `.onChange(of: isVisible)` to start/stop polling

### Decision 5: Polling interval increase

**Choice**: Increase base polling interval from 8s to 15s, with adaptive increase to 30s after 2 minutes of inactivity.

**Rationale**:
- 8s is aggressive for a moderation tool — user is typically reading/interacting, not expecting real-time updates
- 15s is more battery-friendly while still feeling responsive
- 30s for inactive tabs reduces background network traffic when the user is on another tab
- 2-minute inactivity window feels natural — if the user hasn't scrolled or tapped in 2 minutes, they've likely paused reading

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Disk cache consumes device storage | 50 MB cap with aggressive LRU eviction. First eviction at 50 MB, target 40 MB. |
| Stale avatar displayed after profile picture change on Bluesky | 24-hour TTL. User can pull-to-refresh to force re-fetch. |
| @Observable macro requires iOS 17+ | Project already targets iOS 17+. Verified in project.yml. |
| Tab visibility polling may miss edge cases (iPad split view, Slide Over) | Test on iPad. iPad already uses separate wrappers (iPadTimelineView) — will add visibility tracking there too. |
| File-system cache reads blocking main thread | In-memory cache (NSCache) serves most reads. Disk reads happen on the ThumbnailPipeline actor (background thread). |
| Cache invalidation complexity | Simple TTL-based model. No multi-key, no versioning. The 24h window is generous enough to avoid race conditions. |

## Open Questions

- Should `PostEmbedView` (embedded media in timeline) also use the disk cache? Currently uses `ThumbnailImageView` → `ThumbnailPipeline` which will get disk caching automatically.
- Is the avatar stale-TTL of 24h too long for moderation use cases? Moderation profiles change rarely but users may want to see current avatars for block decisions.
