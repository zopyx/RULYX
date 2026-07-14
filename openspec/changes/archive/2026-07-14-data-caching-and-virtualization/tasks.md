## 1. BlueskyAPICache — On-Disk Response Cache

- [ ] 1.1 Create `Sources/Domain/Services/BlueskyAPICache.swift` with an actor-based cache: SHA-256 keyed JSON-file store in caches directory, LRU eviction at 10 MB (target 8 MB), per-account isolation via DID prefix in key
- [ ] 1.2 Implement `cache(key:data:ttl:)` and `cached(key:, maxAge:) -> (Data, isStale: Bool)?` methods
- [ ] 1.3 Add `clearAll()`, `clear(for account:)`, and a `CacheMetricsProviding` protocol exposing hitCount, missCount, currentSize
- [ ] 1.4 Integrate cache into `LiveBlueskyClient.fetchProfile()` — check cache first, return stale data + schedule background refresh
- [ ] 1.5 Integrate cache into `LiveBlueskyClient.fetchLists()` — cache list metadata
- [ ] 1.6 Add "Clear API Cache" button in SettingsView
- [ ] 1.7 Ensure pull-to-refresh bypasses cache (forceRefresh parameter)

## 2. List Member Virtualization

- [ ] 2.1 Define `MemberPage` struct and `PageLoadingState` enum in `ListDetailViewModel.swift`
- [ ] 2.2 Add `@Published var memberPages: [MemberPage]` and `@Published var isLoadingMore = false` to `ListDetailViewModel`
- [ ] 2.3 Convert `loadMembers()` from all-pages loop to `AsyncStream<MemberPage>` that yields pages one at a time
- [ ] 2.4 Update `ListDetailMembersSection.swift` to render paginated members: first 50 immediately, load-more trigger at bottom
- [ ] 2.5 Add on-scroll pagination trigger: `Color.clear.onAppear { loadNextPage() }` at the bottom of the list
- [ ] 2.6 Update the search/filter logic to search only within loaded members, with a note when not all members are loaded yet
- [ ] 2.7 Ensure count badge in list detail header reflects the total count (from API response, not loaded count)

## 3. Performance Monitor Overlay

- [ ] 3.1 Extend `HTTPRequestDebugStore` to record duration per request (start time in `begin()`, end time in `complete()`)
- [ ] 3.2 Add metrics tracking to `HTTPRequestDebugStore`: count per endpoint, average latency, p99 latency, cache hit/miss counters
- [ ] 3.3 Add metrics persistence: save/load metrics JSON from caches directory on app background/foreground
- [ ] 3.4 Create `Sources/App/PerformanceMonitorOverlay.swift` — SwiftUI view for the floating overlay (compact HUD + expanded detail list)
- [ ] 3.5 Create `UIWindow`-based overlay presenter that shows/hides the overlay via three-finger triple-tap gesture
- [ ] 3.6 Add Settings toggle: `@AppStorage("performanceOverlayEnabled")` in SettingsView
- [ ] 3.7 Disable overlay gesture when UIAccessibility.isVoiceOverRunning

## 4. Build & Verify

- [ ] 4.1 Run `xcodegen generate` and verify project compiles
- [ ] 4.2 Build for iOS Simulator: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 4.3 Run `swiftformat Sources Tests` and fix formatting drift
- [ ] 4.4 Run `swiftlint` and address any new warnings
- [ ] 4.5 Verify `openspec validate --change data-caching-and-virtualization --json` passes
