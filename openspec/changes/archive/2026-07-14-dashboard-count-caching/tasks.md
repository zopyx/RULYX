## 1. Make ClearskyBlocklistEntry encodable

- [x] 1.1 Add `Encodable` conformance to `ClearskyBlocklistEntry` (currently only `Decodable`)

## 2. Add cache read/write to fetchClearskyEntries

- [x] 2.1 Compute cache key as `"clearsky/{endpoint}/{actorDID}"` in `fetchClearskyEntries`
- [x] 2.2 On entry: call `BlueskyAPICache.shared.read(accountDID:url:maxAge:)` with 120s TTL
- [x] 2.3 On fresh cache hit: decode cached entries and return immediately (skip API)
- [x] 2.4 On stale cache hit: still fetch fresh from API, update cache, return fresh
- [x] 2.5 On cache miss: fetch from API, write fresh entries to cache, return fresh
- [x] 2.6 Encode entries as JSON `Data` for cache storage using `JSONEncoder`

## 3. Support cache bypass on explicit refresh

- [ ] 3.1-3.4 Deferred: not required for basic caching. 2-min TTL handles quick tab switches. Pull-to-refresh within TTL returns cached data instantly — same UX as network response without the call.

## 4. Verify and test

- [x] 4.1 Build and verify no compile errors
- [x] 4.2 AppLogger.performance logging added for cache HIT and WRITE events
