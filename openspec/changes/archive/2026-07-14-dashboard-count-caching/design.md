## Context

The ListsView (front page / Moderation tab) displays `blockingCount` and `blockedByCount` fetched from ClearSky. These counts come from `fetchClearskyActors(account:endpoint:)` which paginates ALL pages of the ClearSky blocklist API and resolves every actor profile — just to return a count. This happens on every ListsView load, even when the data hasn't changed.

The existing `DashboardCache` provides stale-while-revalidate for the overall dashboard snapshot (lists + profile + counts), but the individual ClearSky fetches still execute on every load. The existing `BlueskyAPICache` actor caches Bluesky PDS responses but is not used for ClearSky data.

## Goals / Non-Goals

**Goals:**
- Cache ClearSky blocklist entries in `BlueskyAPICache` so `fetchBlockingCount` and `fetchBlockedByCount` return from cache within TTL
- 2-minute TTL for ClearSky blocklist data (matching existing `BlueskyAPICache.DefaultTTL` patterns)
- Stale-while-revalidate: show stale count immediately while refreshing in background
- Pull-to-refresh bypasses cache
- Account switch invalidates cache

**Non-Goals:**
- Not changing the ClearSky API endpoint (still uses same paginated fetch on cache miss)
- Not changing `DashboardCache` or `ListsViewModel` — the caching layer is transparent
- Not caching ClearSky lists (separate feature if needed)

## Decisions

### Decision 1: Cache at the `fetchClearskyEntries` level (not higher)

**Chosen:** Cache the raw paginated entries in `BlueskyAPICache` at the `fetchClearskyEntries` level, keyed by `clearsky/{endpoint}/{actorDID}`.

**Alternatives considered:**
- Cache at `fetchClearskyActors` level (includes profile resolution) → larger payload, unnecessary since counts don't need profiles
- Cache at `fetchBlockingCount`/`fetchBlockedByCount` level → works but duplicates logic for each endpoint
- Create a new dedicated cache → unnecessary when `BlueskyAPICache` already exists with the right API

**Why:** `fetchClearskyEntries` is the single bottleneck shared by both count fetches. Caching the raw entries (DIDs + block dates) is ~1 KB per page vs. ~100 KB with resolved profiles. The entries can be deserialized instantly from cache without profile resolution.

### Decision 2: Use existing `BlueskyAPICache` with a 2-minute TTL

**Chosen:** 2-minute TTL for ClearSky entries, matching the existing `DefaultTTL.member` pattern used for profile data.

**Alternatives considered:**
- 5-minute TTL → counts could be too stale for users who actively block between loads
- 30-second TTL → too short to be useful; most users won't revisit within 30s
- No TTL (cache until push-to-refresh) → counts could be hours stale

**Why:** 2 minutes is long enough to skip the fetch on quick tab switches (the common case) but short enough that counts are reasonably current. The UI already shows a spinner next to the count during refresh, so even within the stale window, the user sees fresh data within seconds.

### Decision 3: Serialize encoded `[ClearskyBlocklistEntry]` with the page count

**Chosen:** The cached value is `Data` containing JSON-encoded `[ClearskyBlocklistEntry]`. On cache read, decode entries, compute `.count` for the total, and return.

**Alternatives considered:**
- Cache just the `Int` count → can't refresh individual pages; would need full refetch anyway
- Cache page-by-page → complex invalidation; minimal benefit since entries change rarely

**Why:** The entries array is the smallest unit that can be fed back into the existing code path. No new serialization types needed.

## Risks / Trade-offs

- **[Stale count]** If a ClearSky blocklist changes (user blocked/unblocked someone) within the 2-minute window, the dashboard count lags → Mitigation: 2-minute TTL is short; pull-to-refresh bypasses cache immediately
- **[Cache size]** ClearSky entries for accounts with thousands of blocked actors could be large → Mitigation: entries are small (DID + date string, ~50 bytes each); 10k entries = ~500 KB; BlueskyAPICache's 10 MB eviction limit applies
- **[Background refresh]** If the background refresh fails (network), the stale count persists → Mitigation: on next load, the cache is older than TTL and a full fetch runs; existing error handling in ListsViewModel shows error state
