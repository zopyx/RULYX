## Why

Every time the ListsView (front page) loads, it fetches blocking and blocked-by counts from ClearSky via full pagination of all block list entries plus profile resolution — even though only the count is displayed. This causes slow dashboard loads and unnecessary ClearSky API traffic. Adding application-level caching with TTL avoids repeated network fetches while keeping the displayed count consistent with the detail view.

## What Changes

- Add `BlueskyAPICache`-backed caching to `fetchClearskyEntries` / `fetchClearskyActors`
- `fetchBlockingCount` and `fetchBlockedByCount` read from cache when available and within TTL
- On cache miss or stale TTL, the full paginated fetch runs as before and populates the cache
- Cache is keyed by `clearsky/{endpoint}/{actorDID}` with a 2-minute TTL for count consistency
- Dashboard counts show stale data while a background refresh updates the cache (stale-while-revalidate)
- Pull-to-refresh bypasses the cache (already implemented via `isExplicitRefresh` → `reloadIgnoringLocalCacheData`)
- Cache is cleared on account switch (already handled by `DashboardCache.clearAll()` in `AccountStore`)

## Capabilities

### New Capabilities
- `clearsky-count-cache`: TTL-based caching of ClearSky blocklist counts using the existing `BlueskyAPICache` actor, so the dashboard loads instantly without a full paginated fetch on every visit.

### Modified Capabilities
- `api-response-cache`: Extends the existing API cache spec to cover ClearSky endpoints (currently only Bluesky PDS endpoints are cached).

## Impact

- `LiveBlueskyClient.swift`: Add `BlueskyAPICache` read/write calls to `fetchClearskyEntries` — the central pagination method that feeds all ClearSky blocklist fetches
- `ListsViewModel.swift`: No changes needed — the VM already handles stale-while-revalidate via `DashboardCache`; the BluskyAPICache layer is transparent to it
- `DashboardCache.swift`: Unchanged — still used as snapshot persistence; BlueskyAPICache adds a short-TTL layer above it
- `BlueskyAPICache.swift`: Unchanged — already supports the required read/write/TTL API
