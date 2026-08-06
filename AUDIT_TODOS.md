# RULYX Audit — Prioritized TODO Backlog

> Generated 2026-08-06 from expert audit (race / security / edge / implementation).  
> No code changed — this is the decision backlog. Priorities: **P0** = ship-blocking, **P1** = high, **P2** = medium, **P3** = low/nice-to-have.  
> Effort: **S** < 0.5d · **M** 0.5–2d · **L** 2–5d.  
> Work will proceed in the order you approve — proposed order at bottom.

## How to use
Pick the slice you want first (e.g. “P0 only” or “P0+P1 security”) and say `go`. I will create one branch per TODO and keep this file as source of truth (unchecked → in-progress → checked).

---

## P0 — Critical (data loss / leak / hang / corruption)

| # | Prio | Title | Area | Files | Impact if not fixed | Effort | Proposed fix (1 line) |
|---|------|-------|------|-------|---------------------|--------|------------------------|
| 01 | **P0** | Duplicate account race across `await authenticate` | Race | `Sources/Domain/Services/AccountStore.swift:154,221` | Two concurrent `addAccount(handle:)` both pass `contains` check → duplicate accounts, Keychain overwrite, diverged DIDs | S | Guard with `inFlightHandles: Set<String>` or re-check by DID after auth; serialize `addAccount` |
| 02 | **P0** | `HTTPRequestDebugStore.sanitizeURL` stale `NSRange` — 2nd JWT not redacted | Security | `Sources/Shared/Support/HTTPRequestDebugStore.swift:181-188` | JWT/Klipy key leaks into debug store + export | S | Recompute `NSRange(result.startIndex..., in: result)` per sanitizer iteration |
| 03 | **P0** | `Authorization: Bearer <JWT>` header never sanitized | Security | `Sources/Shared/Support/HTTPRequestDebugStore.swift:158` + `Sources/Domain/Services/HTTPClient.swift:224` | Bearer token visible in debug view if ever logged | S | Add header sanitizer + `sanitizeErrorResponseJSON` for headers |
| 04 | **P0** | `LiveBlueskyClient.clearCache()` fire-and-forget `Task { await clearAll }` breaks account-switch invariant | Race/Security | `Sources/Domain/Services/LiveBlueskyClient.swift:67` / `Sources/App/SettingsView.swift:324` | Stale cross-account cache visible after switch if wrong method called | S | Delete `clearCache()`, keep only `clearAllCaches() async` and migrate call sites |
| 05 | **P0** | Global `URLCache.shared` overwritten twice (50 MB vs 2 GB) | Race/Perf | `Sources/App/RULYXApp.swift:8` vs `Sources/Features/Lists/Profile/MediaBrowserViewModel.swift:115` | Last writer wins, cache thrash, viewer-relative media not accounted for on switch | S | Stop mutating `shared`; use per-session `URLCache` injected into `URLSessionConfiguration` |
| 06 | **P0** | Unbounded pagination `repeat while cursor != nil` — same-cursor infinite loop | Edge/Hang | `Sources/Domain/Services/LiveBlueskyClient.swift:216` / `Sources/Domain/Services/BlueskyProfileService.swift:87,286` / `Sources/Domain/Services/ChatService.swift` | PDS bug → infinite requests, battery/data burn, OOM | S | Cap at 100 pages + break if `nextCursor == currentCursor` |

## P1 — High

| # | Prio | Title | Area | Files | Impact | Effort | Fix |
|---|------|-------|------|-------|--------|--------|-----|
| 07 | **P1** | `CacheMetricsStore` data race (`@unchecked Sendable` + `nonisolated var`) | Race | `Sources/Domain/Services/BlueskyAPICache.swift:24,76` | Torn `hitCount/missCount`, wrong hitRatio, TSan violation | S | Make `hitCount/missCount` actor-isolated on `BlueskyAPICache`, `await` in readers |
| 08 | **P1** | `ChatStore.rebuildConversations` not cancelled on `accountWillSwitch` | Race | `Sources/Domain/Services/ChatStore.swift:103` + `Sources/App/RULYXApp.swift:onReceive activeAccountID` | Cross-account messages briefly shown (in-memory) | S | Hold `Task?` handle, `cancel()` on switch |
| 09 | **P1** | `DashboardCache.load/save` synchronous file IO on `@MainActor` | Perf/Race | `Sources/Domain/Services/DashboardCache.swift` / `Sources/Features/Lists/ListsViewModel.swift:80` | UI jank, race with `clearAll` removing directory mid-read | M | Make `DashboardCache` actor or move IO to `Task.detached` |
| 10 | **P1** | `RelationshipCache` same as above (sync IO + orphan files) | Perf/Race | `Sources/Domain/Services/RelationshipCache.swift` | Same | M | Same as 09 |
| 11 | **P1** | `BlueskyAPICache.clearAll` removes directory while concurrent `read/write` in flight | Race | `Sources/Domain/Services/BlueskyAPICache.swift:154` | Sporadic miss, suppressed Cocoa 260 errors | S | Serialize via actor (already actor) + ensure callers `await` — covered by 04 |
| 12 | **P1** | Search has no debounce / cancellation | Edge/Perf | `Sources/Features/Lists/CustomSearchView.swift` / `Sources/Features/Lists/MentionsSearchView.swift` / `BlueskyProfileService` | Rapid typing → many requests, rate-limit hits | S | `searchTask?.cancel()` + 300 ms debounce, check `Task.isCancelled` before apply |
| 13 | **P1** | `ListsViewModel.load` / `NotificationViewModel.load` not coalesced / not cancellable | Race | `Sources/Features/Lists/ListsViewModel.swift:108` / `Sources/Features/Notifications/NotificationViewModel.swift:66` | Flicker, stale `blockingCount`, last-write-wins | S | Store `loadTask: Task<Void,Never>?`, cancel on re-entry |
| 14 | **P1** | `InflightManager` dedup key too weak (`method:url` only) + not used everywhere | Perf/Race | `Sources/Domain/Services/HTTPClient.swift:142,218` | Missed coalescing, rare poisoning if query order differs | S | Canonicalize `URLComponents` + route all `data(for:)` through `dedupedData` or document |
| 15 | **P1** | `removeAccount` leaves orphaned per-DID caches | Edge | `Sources/Domain/Services/AccountStore.swift:322` + `DashboardCache`/`RelationshipCache`/`BlueskyAPICache` | Disk grows, stale data re-appears if DID reused | S | Call `BlueskyAPICache.clear(for:)`, `DashboardCache.clear(forKey:)`, `RelationshipCache.clear(forKey:)` on remove |
| 16 | **P1** | `BlueskySessionService.requiresExplicitReauthentication` substring match fragile | Edge | `Sources/Domain/Services/BlueskySessionService.swift:236` | `invalid_token` / `expire` miss → wrong retry path, extra reauth sheet | S | Match error `code` (`ExpiredToken`) not message substring |
| 17 | **P1** | `AppLogger` privacy — handles logged as `.public` in switch | Security | `Sources/Domain/Services/AccountStore.swift:376,393` / `Sources/Shared/Support/AppLogger.swift` | PII in unified log | S | Change to `.private` or `.sensitive` |
| 18 | **P1** | `Secrets.xcconfig` + `KlipyAPIKey` in `Info.plist` in IPA | Security | `Config/Secrets.xcconfig` / `project.yml: KlipyAPIKey: $(KLIPY_API_KEY)` | Key extractable via `strings` | S | Verify `.gitignore`, add pre-commit hook, document rotation runbook |

## P2 — Medium

| # | Prio | Title | Area | Files | Impact | Effort | Fix |
|---|------|-------|------|-------|--------|--------|-----|
| 19 | **P2** | `LiveBlueskyClient` God class (~2400 lines, 9 protocols) | Arch | `Sources/Domain/Services/LiveBlueskyClient.swift:24` | Merge conflicts, testability | L | Split into `ListClient`/`ProfileClient`/`FeedClient` actors, compose |
| 20 | **P2** | Stale-while-revalidate `Task { [weak self] }` can silently drop refresh if client deallocates | Race | `Sources/Domain/Services/LiveBlueskyClient.swift:122` | Stale dashboard forever | S | Strong capture or schedule via store-owned task |
| 21 | **P2** | `BlueskySessionService.invalidateAuthenticationState` clears `URLCache.shared` + all disk caches on any auth failure | Edge | `Sources/Domain/Services/BlueskySessionService.swift:224` | Over-clear on transient 401 (rate limit) | S | Only clear session cache on `revoked`/`invalidated`, not on `expired` |
| 22 | **P2** | `HTTPRequestDebugStore.maxAge` 24h but comment says 3h; `purgeOldEntries` logic off | Impl | `Sources/Shared/Support/HTTPRequestDebugStore.swift:59,139` | Log grows 8× expected | S | Align comment/value or make configurable |
| 23 | **P2** | `PostClassificationView.results[modelID]!` force-unwrap | Edge | `Sources/Domain/AI/PostClassificationView.swift:103` | Trap if model missing | S | `guard let` + fallback |
| 24 | **P2** | `NotificationCenter.addObserver(..., queue: .main)` in `AccountStore.init` never removed | Impl | `Sources/Domain/Services/AccountStore.swift:76,88,102` | Leaked observer in tests (store is singleton in prod) | S | Store tokens + remove in `deinit` |
| 25 | **P2** | `AIModelManagementView` etc use unstructured `Task { await ... }` without cancellation | Race | `Sources/App/AIModelManagementView.swift:18` + many Chat/Profile views | Work continues after view dismissed | S | Use `.task` modifier or store `Task` handle |
| 26 | **P2** | `FeedStore` per-DID keys correct but `clearAllCaches` docs say “NOT reset on switch — by design” — not obvious | Impl | `Sources/Domain/Services/FeedStore.swift:18` | Future dev may incorrectly clear | S | Add doc comment + test asserting not-cleared |
| 27 | **P2** | `CertificatePinningDelegate` uses `SecTrustEvaluateWithError` + `SecTrustGetTrustResult` double-check — redundant, logs misleading | Security | `Sources/Domain/Services/HTTPClient.swift:58` | Log noise | S | Drop `GetTrustResult` check, keep `EvaluateWithError` |
| 28 | **P2** | `GIFService.migrateLegacyAPIKey` reads `UserDefaults klipyAPIKey` without synchronization | Edge | `Sources/Domain/Services/GIFService.swift:141` | Rare race on first launch if two `GIFService()` inits race | S | Guard with `dispatch_once` / actor |
| 29 | **P2** | `iCloudAccountSync` posts `[[String:String]]` via `NotificationCenter` unencrypted in transit (in-process only) — correct, but no validation of entries | Security | `Sources/Shared/Support/iCloudAccountSync.swift:28,102` | Malicious iCloud KV could inject fake handles | M | Validate DID format, handle regex before `mergeCloudAccounts` |
| 30 | **P2** | `BlueskyProfileViewModel` splits viewer state (`activeAccount`) vs data (`preferredSearchAccount`) — correct but fragile; iPad inspector duplicates logic | Arch | `Sources/Features/Lists/BlueskyProfileViewModel.swift` / `Sources/App/iPad/iPadProfileInspector.swift:59` | Future bug where mutation uses wrong account | M | Extract `AccountContextResolver` helper + test |

## P3 — Low / Nice-to-have

| # | Prio | Title | Area | Files | Impact | Effort | Fix |
|---|------|-------|------|-------|--------|--------|-----|
| 31 | **P3** | Static `URL(string:)!` for constants — acceptable but inconsistent with `try!` elsewhere | Impl | `Sources/Shared/Support/URL+Bluesky.swift:7` / `Sources/Domain/AI/LiveAIService.swift:20` | Trap if typo | S | `guard let` + `precondition` |
| 32 | **P3** | `PreviewBlueskyClient` DTO drift vs live lexicon (`listItemCount` etc) | Impl | `Sources/Domain/Services/PreviewBlueskyClient.swift` | Screenshot tests false green | M | Generate mock from shared DTOs |
| 33 | **P3** | `TimelineState` enum vs boolean flags — already good, but `FeedTimelineViewModel` still has `isLoading` booleans alongside | Arch | `Sources/Features/Timeline/TimelineState.swift` | Minor confusion | S | Remove booleans, use enum only |
| 34 | **P3** | `ThumbnailImageView` + `FreshAvatarImage` both do `.task(id: url)` avatar fetch — duplication | Perf | `Sources/Shared/Components/ThumbnailImageView.swift:260` / `Sources/Shared/Components/FreshAvatarImage.swift:31` | 2 fetches for same URL | S | Share `AvatarCache` |
| 35 | **P3** | `xcodegen` `project.yml` `MARKETING_VERSION` 1.0.17 vs `CURRENT_PROJECT_VERSION` 71 — no automation | Impl | `project.yml` | Manual bump errors | S | Add `make bump` lane |
| 36 | **P3** | `swiftformat --lint` + `swiftlint` not in CI gate (only local) | Impl | `Makefile` | Style drift | S | Add to GitHub Actions |
| 37 | **P3** | `HTTPClient.defaultPinnedHashes` comment says “raw public key bytes (SecKeyCopyExternalRepresentation), NOT SPKI hashes” — verify against pinning impl `sha256PublicKeyHash` which hashes SPKI? Comment/code mismatch | Security | `Sources/Domain/Services/HTTPClient.swift:169` | Confusing rotation | S | Align comment to impl |
| 38 | **P3** | `ListBatchController` / `ListMergeController` not actor-isolated — bulk add could interleave with `fetchListMembers` | Race | `Sources/Features/Lists/ListBatchController.swift` | Rare count mismatch | M | Make actor |
| 39 | **P3** | `AnalyticsStore` keyed by post URI (post-global) but persists per-install — no TTL | Edge | `Sources/Domain/Services/AnalyticsStore.swift:18` | Unbounded growth | S | Add LRU / 30d TTL |
| 40 | **P3** | Docs: `AGENTS.md` “Blocking / Blocked-By Consistency” rule not enforced by test | Impl | `AGENTS.md` | Regression risk | S | Add unit test asserting both counts use `fetchClearskyActors` |

---

## Proposed working order (change it as you like)

**Option A — Risk-first (recommended for next release):**
`01 → 02+03 → 04 → 05 → 06 → 07 → 12 → 13 → 15 → 16 → 08 → 09/10 → then P2 in numeric order`

**Option B — Security-first (if shipping to App Store soon):**
`02+03 → 05 → 17 → 18 → 29 → 27 → 01 → 04 → 06 → rest`

**Option C — Quick wins first (momentum):**
`02,03,04,06,07` (all S) → `12,13,15,22,23,31` → `01,05,09,10,19`

All TODOs are `pending` — tell me e.g. `do P0` or `do 01,02,04,06` or `do option A` and I’ll start. Each TODO will be one branch + one PR with tests.

### How I’d report progress
Every PR will include the table row + verification (tests / `swiftlint` / manual check) and update this file (`- [x]`). The “Files modified” table required by `AGENTS.md` will be in each PR description.

---

*Do not start work until you confirm order. Reply with the numbers or option letter.*
