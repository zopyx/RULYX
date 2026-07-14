## Why

Navigation in RULYX is still unnecessarily slow despite the recent image-caching work. Every time you open a profile, a list, or a list detail, the app makes fresh API calls — even for data you just viewed seconds ago. Lists with 1000+ members freeze the UI during initial load because all members are fetched before rendering. And there's no visibility into what's actually slow — developers and power users have to guess at bottlenecks. These three enhancements together eliminate the remaining latency pain points.

## What Changes

- **Bluesky API response cache**: Add a JSON-file-based on-disk cache for Bluesky API responses (profiles, lists, list members, relationship actors) keyed by endpoint + account. Cached data is displayed instantly while a background refresh updates it. Follows the existing `DashboardCache` pattern. Entries have a configurable TTL (default 5 minutes for lists/members, 2 minutes for profiles).
- **List member virtualization**: Convert `ListDetailView` member loading from one-shot fetch-all to paginated lazy loading. Only the first page (~50 members) is loaded initially; subsequent pages load on-demand as the user scrolls. This eliminates startup freeze for lists with thousands of members.
- **HTTP debug stats overlay**: Extend the existing `HTTPRequestDebugStore` with a floating debug overlay (shake gesture or settings toggle) showing real-time stats: request count, average latency, cache hit rate, slowest endpoint, and last N request details. Persist stats across app launches.

## Capabilities

### New Capabilities
- `api-response-cache`: On-disk caching for Bluesky API responses (profiles, lists, list members, relationships) with configurable TTL and per-account isolation.
- `list-member-virtualization`: Paginated/lazy loading for list member views — only visible pages are fetched and rendered.
- `performance-monitor`: In-app debug overlay showing HTTP request metrics, cache performance, and timing data.

### Modified Capabilities
- *(none — all three are new capabilities)*

## Impact

- **Files touched**: `LiveBlueskyClient.swift`, `BlueskyListService.swift`, `ListDetailView.swift`, `ListDetailViewModel.swift`, `ListDetailMembersSection.swift`, `BlueskyProfileView.swift`, `BlueskyProfileViewModel.swift`, `ListsViewModel.swift`, `RelationshipsView.swift`, `HTTPRequestDebugStore.swift`, `HTTPRequestDebugView.swift`, `HTTPDebugStatsView.swift`, `AppLogger.swift`
- **New files**: `BlueskyAPICache.swift`, `PerformanceMonitorOverlay.swift`, `ListMemberLoadingState.swift`
- **No new external dependencies**
- **No data model changes**
- **Risk**: Stale cached data shown after API-side changes — mitigated by short TTLs and pull-to-refresh overriding cache
