## Context

The app has three remaining performance pain points after the image-caching work:

1. **No API-level caching** — Every navigation triggers fresh API calls. Profile inspection makes 5+ sequential calls. List detail re-fetches all members every time. The existing `DashboardCache` (JSON file per account) proves the pattern works, but it only covers the dashboard view.

2. **List members load all-at-once** — `ListDetailViewModel` fetches all pages of members upfront via `fetchListMembersPage()` in a loop. For lists with 2000+ members this means 20+ sequential API calls before the first member appears.

3. **No performance visibility** — The only debug tool is `HTTPRequestDebugView` which shows raw request URLs but no metrics. Without data on which endpoints are slow, optimizations are guesswork.

## Goals / Non-Goals

**Goals:**
- Re-opening a profile or list within minutes loads instantly from cache
- Lists with 5000+ members display the first page in <1 second instead of freezing for 10+ seconds
- Developers and power users can see real-time API latency and cache performance
- All three features are purely additive — no behavior change for normal use

**Non-Goals:**
- No network-layer intercepting or proxy — caching is at the service layer, not the HTTP layer
- No change to the authentication flow or session management
- No persistent offline support — caching is for recency, not offline mode
- No UI changes to list member interaction (swipe, context menu) — only the loading pattern changes
- No push notifications or server-side changes

## Decisions

### Decision 1: Service-layer cache (not HTTP cache)

**Choice**: Wrap `LiveBlueskyClient` methods with a caching decorator rather than using `URLCache` or a URL protocol.

**Rationale**:
- `URLCache` caches raw HTTP responses, but many of our API responses are already compressed or contain tokens — caching at the HTTP layer would cache auth tokens
- Service-layer caching lets us cache decoded model objects as JSON, which is smaller and avoids re-decoding
- We can selectively cache: cache profiles and lists but skip auth and chat endpoints
- Follows the existing `DashboardCache` pattern (JSON file per key)
- Easy to instrument for the performance monitor (count hits/misses)

**Implementation**:
- New `BlueskyAPICache` actor with methods like `cache(key:data:ttl:)` and `cached(key:, maxAge:) -> Data?`
- Each cached response is a JSON file in `caches/com.ajung.RULUX.APICache/`
- Key format: `SHA256("\(accountDID)/\(normalizedURL)")`
- Cache entry metadata (timestamp, TTL) stored as extended attributes or a sidecar JSON
- 10 MB cap with LRU eviction (same as ThumbnailPipeline pattern)

### Decision 2: In-request staleness pattern

**Choice**: "Stale-while-revalidate" — return cached data immediately, then refresh in the background.

**Rationale**:
- SwiftUI shows placeholders/spinners during loading. If we show cached data and refresh silently, the user sees instant content while staying fresh.
- Matches the existing `ListsViewModel` pattern where `isFromCache = true` followed by background refresh.
- The `BlueskyProfileViewModel.load()` already has a `loadIfNeeded` guard — extending it with cache-first semantics is natural.

**Implementation**:
- `BlueskyAPICache` has a `read(key:, maxAge:) -> (data: Data, isStale: Bool)?` method
- When stale: return data immediately but signal the caller to schedule a refresh
- When fresh: return data, no refresh needed
- When miss: fetch from network normally

### Decision 3: Paginated list members via async sequence

**Choice**: Replace the current all-pages loop with `AsyncStream`-based paginated loading.

**Rationale**:
- Current code in `ListDetailViewModel+Data.swift` loops with `while cursor != nil` to fetch all pages
- AsyncStream lets the view model yield pages one at a time as they arrive
- The view observes a `membersPages: [MemberPage]` array where `MemberPage` has `[BlueskyListMember] + cursor`
- Each page renders independently — the first page appears immediately, subsequent pages append as they load
- The `ListDetailMembersSection` view reads `membersPages.flatMap(\.members)` for display and `membersPages.last?.cursor` to decide whether to show a "load more" trigger

**Implementation**:
```swift
struct MemberPage: Identifiable {
    let id: Int // page index
    let members: [BlueskyListMember]
    let cursor: String?
    let isLoading: Bool
    let error: String?
}
```
- `ListDetailViewModel` has a `@Published var memberPages: [MemberPage] = []`
- `loadMembers()` returns an `AsyncStream<MemberPage>` that yields pages sequentially
- View uses `ForEach(memberPages.flatMap(\.members), id: \.recordURI)`
- Bottom-of-list `.onAppear` triggers `loadNextPage()` which calls `fetchListMembersPage(cursor:)`
- Search filters against the union of all loaded members

### Decision 4: Performance monitor as overlay scene

**Choice**: A floating `UIWindowScene` overlay (similar to FPS counters in games) activated by gesture or settings toggle.

**Rationale**:
- A floating overlay works across all views without modifying each view's hierarchy
- Three-finger triple-tap is a standard iOS debug gesture (used in Xcode's Slow Animations / Color Blended Layers)
- Compact default: small HUD at top of screen showing 4 key metrics
- Expanded on tap: scrollable list of recent requests with full details

**Implementation**:
- `PerformanceMonitorOverlay` is a SwiftUI view wrapped in `UIHostingController`
- Presented as a floating window (windowLevel = .statusBar + 1)
- Metrics collected by extending `HTTPRequestDebugStore.begin()` to record start time, then record duration on completion
- Cache metrics from `BlueskyAPICache` exposed via a protocol `CacheMetricsProviding`
- Persisted via `Codable` to a JSON file in caches directory
- Settings toggle: `@AppStorage("performanceOverlayEnabled")` in SettingsView

### Decision 5: Granular loading states for pagination

**Choice**: Three-state enum per page instead of boolean flags.

**Rationale**:
- The current codebase already uses `LoadableState` patterns (idle→loading→loaded→error)
- Each page needs its own independent state
- Follows the existing convention from `TimelineState`

**Implementation**:
```swift
enum PageLoadingState: Equatable {
    case pending    // not yet requested
    case loading    // currently fetching
    case loaded     // successfully loaded
    case failed(String) // error message
}
```

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Stale cached data after API-side changes | Short TTLs (2m profiles, 5m lists). Pull-to-refresh always bypasses cache. |
| Cache eviction deletes data user is about to view | LRU is access-time-based, so actively viewed data is never evicted. |
| Pagination breaks existing search/filter | Search filters client-side against loaded members. If no match found, offer a "search server-side" fallback. User is warned that search only covers loaded members. |
| Floating overlay interferes with navigation | Overlay is passthrough (isUserInteractionEnabled = false) in compact mode. Only expanded mode captures taps. |
| Cache directory growth | 10 MB hard cap. User can clear from Settings. OS can purge caches directory under storage pressure. |
| Three-finger triple-tap conflicts with VoiceOver | Feature is disabled when VoiceOver is active. Setting toggle serves as alternative activation. |

## Open Questions

- Should the API cache be automatically invalidated when the user's session token changes? (Probably yes — different sessions may see different data for the same account.)
- Should `BlueskyAPICache` be a generic cache (any Codable) or typed for specific response types? (Generic is simpler for now.)
- Performance monitor: should we track view body render times (slow SwiftUI re-evals) or only network metrics? (Start with network/cache only; view metrics are harder to collect safely.)
