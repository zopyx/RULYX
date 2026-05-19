# RULYX — Expert Panel Review

**Date:** 2026-05-19
**Build under review:** TestFlight 1.0 (37) + current working tree
**Reviewer:** Multi-agent expert panel (UX, Accessibility, Architecture, Security, Performance, Testing, i18n)
**Verdict:** Solid mid-stage product with strong i18n and clean networking layer; held back by a god-object DI, a few accessibility regressions, scattered iPad dead code, and gaps in integration/UI tests.

---

## Score Card

| Domain | Score | One-line takeaway |
|---|---|---|
| **Information architecture & nav** | 6.5/10 | Clean TabView; custom swipe gesture and `horizontalSizeClass` dead code muddy the iPhone-only mandate. |
| **Visual design & polish** | 7/10 | Cohesive palette and dark mode; spacing inconsistent, banner state changes lack transitions. |
| **Interaction design** | 6/10 | Right components, missing feedback — no haptics, search debounce invisible, no completion toasts. |
| **Onboarding & first-run** | 7.5/10 | Modal with feature grid is solid; doesn't surface the account-add precondition. |
| **Splash & launch** | 5/10 | 3-4s mandatory animation on every cold start is indulgent for a moderation utility. |
| **VoiceOver coverage** | 6/10 | Custom `appButtonAccessibility()` helpers exist but icon-only buttons skip labels in several screens. |
| **Dynamic Type** | 5/10 | Semantic fonts plus `minimumScaleFactor(0.5)` + fixed sizes effectively cap large text. |
| **Color contrast & non-color cues** | 5/10 | Red/green char counter, status badges, and 0.8-opacity chevrons signal by color alone. |
| **Reduced Motion** | 8/10 | Centralized `AppStyling` motion helpers; respects setting end-to-end including splash. |
| **Tap targets & keyboard nav** | 4/10 | 24-pt image delete buttons and icon-only toolbar items fall under the 44-pt floor. |
| **Architecture cleanliness** | 6/10 | `AppDependencies` is a god object; extension-style "+File" splits scatter logic. |
| **Concurrency correctness** | 7/10 | Swift-6 isolation mostly correct; `nonisolated(unsafe)` Keychain access and static caches still leak. |
| **Networking design** | 8/10 | Sendable executor, debug store, preemptive token refresh — solid. |
| **Error handling** | 7.5/10 | `AppError` mapping is good; cache layer silently swallows failures with `try?`. |
| **Code organization** | 6/10 | 828-line `ListDetailView`, 675-line `ListsView`, sprawling `+Extensions` per VM. |
| **Credential & token storage** | 7/10 | Keychain is properly used with device-only access; app password is passed around in memory more than necessary. |
| **Network & transport security** | 7/10 | TLS-only PDS, no certificate pinning, debug store redacts only Klipy keys. |
| **Logging hygiene** | 6/10 | Handles logged as `privacy: .public`; JWT may persist in debug error responses. |
| **Auth/biometric implementation** | 8/10 | LAContext + passcode fallback correct; no rate limit on failed attempts. |
| **Privacy & data minimization** | 6.5/10 | `PrivacyInfo.xcprivacy` declares only UserDefaults — iCloud KVS and network use undeclared. |
| **Launch perf** | 6/10 | Two `TimelineView(.animation)` + 60-particle Canvas on splash burn CPU before first useful frame. |
| **Scroll perf** | 5/10 | Per-row `DateFormatter()`, raw `AsyncImage`, no windowing in search results. |
| **Network efficiency** | 4/10 | Polling has no app-state awareness; no request deduping for rapid account switches. |
| **Memory footprint** | 6/10 | `ThumbnailImageView` does the right thing; full export buffers held in memory before write. |
| **Battery / background impact** | 5/10 | Heartbeat + chat poll run regardless of foreground state; no Network reachability gating. |
| **Unit test coverage** | 7/10 | 37 unit suites, MockURLProtocol, MockKeychainService — solid. |
| **Integration test coverage** | 4/10 | `LiveAuthenticationTests` only covers happy-path login. |
| **UI test coverage** | 3/10 | Single `RULYXUITests.swift` file — tab smoke only. |
| **Test quality** | 6/10 | Behavior-asserting, but no chaos/latency injection. |
| **CI/build determinism** | 7/10 | Fixed simulator, fresh derived data option, localization gate — good baseline. |
| **Translation coverage** | 7/10 | 16 bundles at parity per validator; `ar.json` has an orphan key. |
| **String API consistency** | 5/10 | Mixed `String(localized:)`, `loc(...)`, `Text("key")` patterns; no enforced canonical form. |
| **Plural & gender rules** | 5/10 | `_one/_other` only — breaks Russian/Arabic/Polish CLDR plural categories. |
| **RTL correctness** | 6/10 | Layout direction flips globally; no explicit symbol mirroring or directional icon variants. |
| **Locale-aware formatting** | 4/10 | `DateFormatter` instances without `.locale` assignment; per-call allocation in scroll paths. |
| **Weighted average** | **6.2/10** | **Functional, shippable, with concrete next-quarter wins on a11y + perf + tests.** |

---

## 1. UX & Frontend (avg 6.4/10)

### Information architecture & navigation — 6.5/10
Five-tab `TabView` with `NavigationStack` per tab is the right shape (`Sources/App/RootView.swift:30-102`). The custom `DragGesture` tab-swap at `RootView.swift:107-126` is undiscoverable and competes with content scroll — recommend removing.

### Visual design — 7/10
Palette and dark mode work; rhythm breaks in `ListDetailView.swift` (mixed `.padding(16)` and `.padding(.vertical, 4)`). The `RootView.swift:103` `.tint(...)` swap to red on Clearsky outage is jarring and untransitioned.

### Interaction design — 6/10
- Export flow (`ListDetailView.swift:616-699`) shows progress, no completion toast or haptic.
- Search debounces 300 ms (`ListDetailView.swift:577`) with no "searching" state.
- Batch cancel lacks destructive confirmation.

### Onboarding — 7.5/10
Modal at `RootView.swift:132-185` covers the basics but doesn't enforce account add — `AccountTabView.swift:17-22` is where new users actually need to land.

### Splash — 5/10
`SplashScreenView.swift:97-148` runs a 3-second auto-dismiss with a 60-particle `Canvas` star field. Beautiful but expensive at first-impression cold start. Recommend a 1-shot `@AppStorage("hasSplashed")` gate.

### Top UX fixes
1. **Skip splash after first launch.** `SplashScreenView.swift:141-147` — gate the 3-second wait behind first-run.
2. **Add completion feedback on export.** `ListDetailView.swift:616-699` — `UINotificationFeedbackGenerator().notificationOccurred(.success)` + inline toast.
3. **Show search-in-flight state.** `ListDetailView.swift:575-588` — render a faint inline `ProgressView` while debouncing.
4. **Delete `horizontalSizeClass` branches.** `ProfileInspectorView.swift:102, 348` — dead code per AGENTS.md ("No iPad code paths").
5. **Remove custom tab swipe gesture.** `RootView.swift:107-126` — conflicts with vertical scroll.

> **Caveat:** UX agent flagged `ModerationSplitView` as an "empty wrapper" smell — that's actually correct per `AGENTS.md` ("thin wrapper that always delegates to ListsView"). Leaving it as-is.

---

## 2. Accessibility (avg 5.6/10)

### VoiceOver — 6/10
Custom `appButtonAccessibility()` exists, but icon-only `Button { } label: { Image(systemName: "plus") }` patterns in `ListsView.swift:134, 181, 243, 255` ship without `accessibilityLabel`. `ComposePostView.swift:122` (delete-image button) is icon-only too.

### Dynamic Type — 5/10
`ListRowView.swift:13` uses `minimumScaleFactor(0.5)` — at xxxLarge that crushes display names. `ComposePostView.swift:214` hardcodes `.font(.system(size:))`. Use `.appFont(.body)` or omit `minimumScaleFactor`.

### Color contrast & non-color cues — 5/10
- Char counter color flip in `ComposePostView.swift:61` — no icon or text addition.
- `AccountRowView.swift:62-75` active-account badge is color-only.
- `ListsView.swift:417` chevron at 0.8 opacity is suspect against the secondary background.

### Reduced Motion — 8/10
`AppStyling.swift:138-150` centralizes a motion-aware animation helper; `SplashScreenView.swift:97-100` early-returns on reduced motion. Good.

### Tap targets & keyboard — 4/10
Multiple sub-44-pt buttons: image-delete circles in compose flow, icon-only toolbar items. No explicit focus management for keyboard users.

### Top 5 a11y fixes
1. **Label icon-only buttons.** `ListsView.swift:134, 181, 243, 255`, `ComposePostView.swift:122` — every `Button { } label: { Image(systemName:) }` needs `.accessibilityLabel(loc("..."))`.
2. **Replace color-only char counter with icon+text.** `ComposePostView.swift:61` — add SF Symbol + text so colorblind users see the warning.
3. **Drop `minimumScaleFactor(0.5)`.** `ListRowView.swift:13` — allow wrap or `.lineLimit(2)` so xxxLarge Dynamic Type isn't crushed to illegible glyphs.
4. **Enlarge sub-44pt tap targets.** `ComposePostView.swift:122` and similar image-remove circles — wrap with `.contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44)`.
5. **Add text and label to status badges.** `AccountRowView.swift:62-75` — "Active" indicator needs `Text` alongside color and an `.accessibilityLabel("account.active")`.

---

## 3. Architecture & Code Quality (avg 6.5/10)

### Architecture cleanliness — 6/10
`AppDependencies` (`Sources/App/AppDependencies.swift:4-69`) holds 13 heterogeneous services with no protocol seam. Every view receives the whole bag via environment objects, which is convenient but cripples per-feature mockability.

### Concurrency correctness — 7/10
Strict-concurrency adoption is honest but partial:
- **The crash we just fixed** (`ClearskyHeartbeatService.swift:22`) was a unit-conversion bug producing a 10-nanosecond sleep loop — that's the iPad SIGBUS root cause from `crashlog.crash`.
- `GIFService.swift:40, 97` uses `nonisolated(unsafe)` for Keychain — race-prone if multiple accounts seed simultaneously.
- `DashboardCache` / `RelationshipCache` are static enums doing `FileManager` I/O with no isolation.

### Networking — 8/10
`BlueskyRequestExecutor` is `Sendable` and off-MainActor; `HTTPClient` cleanly composes user-agent + debug + pinning delegate. Token refresh with 60-s preemptive window is well-thought-out (`BlueskySessionService.swift:302`). One concern: 401 retry has no exponential backoff (`BlueskySessionService.swift:90-107`).

### Error handling — 7.5/10
`AppError` normalizes URLError + DecodingError + Bluesky API error into semantic categories with localized messages. The weakness is cache I/O — 9 `try?` sites in `DashboardCache.swift:30-44` silently swallow failures.

### Code organization — 6/10
- `ListDetailView.swift` is **828 lines** (`wc -l` confirmed).
- `ListsView.swift` is **675 lines**.
- The "+Data / +Search / +Bulk / +State / +Helpers" extension fan-out for `ListDetailViewModel` and `ListDetailView` spreads coupled logic across 8+ files — discoverability suffers.

### Top 5 architectural fixes
1. **Break the god object.** `AppDependencies.swift:4-69` — extract `protocol ListsServices`, `protocol ChatServices`, `protocol AccountServices` and inject only what each feature consumes; AppDependencies becomes a thin wiring layer.
2. **Remove `nonisolated(unsafe)` from Keychain access.** `GIFService.swift:40, 97` — wrap in `@MainActor` or a dedicated actor; today's race is small only because nobody multi-seeds.
3. **Stop swallowing cache failures.** `DashboardCache.swift:30-44` — replace `try?` with `do/catch` + `AppLogger.persistence.error(...)`; promote return type to `Result<…, CacheError>` where callers care.
4. **Add jittered backoff to 401 retry.** `BlueskySessionService.swift:99-106` — cap at 3 attempts, jitter 1/2/4 s; today's loop can hammer the auth endpoint on systemic failure.
5. **Split the 828-line view.** `ListDetailView.swift` — extract `ListMembersSection`, `ListMetadataSection`, `ListBulkActionsSection` as siblings; each <300 LOC, individually testable.

---

## 4. Security (avg 7/10)

### Credential storage — 7/10
`KeychainService` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — correct. App passwords stored in keychain. Concern: `GIFService` seeds a hardcoded Klipy API key on first launch (`GIFService.swift:53`).

### Network/transport — 7/10
HTTPS enforced for PDS URLs (`BlueskySessionService.swift:284-286`). No cert pinning. Domain entryway resolution accepts unverified user-supplied domains.

### Logging hygiene — 6/10
`AccountStore.swift:200` logs handles as `privacy: .public`. `HTTPRequestDebugStore.swift:104-108` regex-redacts Klipy keys only — JWT bearer tokens in error responses would persist.

### Auth/biometric — 8/10
LAContext + passcode fallback (`AppLockManager.swift:89-95`). No rate limit on failed attempts.

### Privacy & data minimization — 6.5/10
`iCloudAccountSync.swift:32-52` pushes handle/DID/PDS URL into `NSUbiquitousKeyValueStore` in cleartext. `PrivacyInfo.xcprivacy` declares only UserDefaults — missing iCloud and network entries.

### Top 5 security fixes
1. **Strip JWTs from debug error JSON before persisting.** `HTTPRequestDebugStore.swift:76-84`, `HTTPClient.swift:43` — redact `authorization`, `accessJwt`, `refreshJwt` keys at the same chokepoint that already strips Klipy keys.
2. **Rotate or remove the hardcoded Klipy API key.** `GIFService.swift:53` — either fetch from a server you control on first launch, or rotate to a low-value key documented in the threat model.
3. **Encrypt or opt-in-gate iCloud account sync.** `iCloudAccountSync.swift:34-44` — handle/DID in `NSUbiquitousKeyValueStore` is cleartext today; either wrap with a per-device symmetric key or default-disable and surface opt-in copy.
4. **Update `PrivacyInfo.xcprivacy` to declare iCloud + network.** Only UserDefaults is declared today; App Store Review will flag this when push manifest auditing tightens.
5. **Add biometric retry backoff.** `AppLockManager.swift:79-101` — currently relies entirely on OS lockout; add app-level cooldown after 5 fails.

---

## 5. Performance (avg 5.2/10)

### Launch — 6/10
The splash itself drives this: `SplashScreenView.swift:155-199` runs two `TimelineView(.animation)` instances (background orbs + 60-star Canvas). On a cold start this competes with deserialization and account restore.

### Scroll — 5/10
- `ClearskyListsView.swift:105` creates `DateFormatter()` per call.
- `CustomSearchView.swift:287` uses `ForEach` over the full result array without windowing.
- `AsyncImage` is used directly for owner avatars in list detail — bypassing the `ThumbnailImageView` cache.

### Network efficiency — 4/10
- `ChatStore.startPolling()` (`Sources/Domain/Services/ChatStore.swift:274-281`) runs an infinite 5-second loop with no `UIApplication.didEnterBackgroundNotification` pause.
- `ClearskyHeartbeatService` now has the correct interval after today's fix, but still pings unconditionally regardless of network reachability or app state.
- No request deduping on rapid account switches.

### Memory — 6/10
`ThumbnailImageView` is well-engineered (downsampling + NSCache). `ListDetailView.swift:616-695` buffers entire export payload in memory before writing — fine for small lists, awkward at 50k+ members.

### Battery / background — 5/10
Heartbeat + chat poll continue while in background. No `.onChange(of: scenePhase)` gates.

### Top 5 perf fixes
1. **Gate background pollers on `scenePhase`.** `ChatStore.swift:274-281`, `ClearskyHeartbeatService.swift` — `.onChange(of: scenePhase)` to pause on `.background` / `.inactive`; today both run forever.
2. **Skip splash effects after first launch.** `SplashScreenView.swift:155-199` — gate `StarField` + second `TimelineView` behind `@AppStorage("hasSplashed")`; the 60-particle Canvas is the single biggest cold-start CPU spike.
3. **Cache `DateFormatter` and `ISO8601DateFormatter`.** `ClearskyListsView.swift:105`, `ChatMessageBubble.swift:9-12` — hoist to file-scope `static let` or view-model property; per-call allocation in scroll hot paths is wasted work.
4. **Replace bare `AsyncImage` with `ThumbnailImageView`.** `ListDetailView.swift:411-420` (and audit other call sites) — bypassing the existing NSCache + downsampling helper costs memory and decode time on every appearance.
5. **Stream large exports to disk.** `ListDetailView.swift:616-695` — buffering all rows in memory before writing is fine at 1k members, painful at 50k; write incrementally via `FileHandle`.

---

## 6. Testing (avg 5.4/10)

### Inventory
- **Unit:** 37 files in `Tests/RULYXTests/`. Mocks for Keychain, URLProtocol, authenticating client.
- **UI:** Single `UITests/RULYXUITests/RULYXUITests.swift` — tab smoke only.

### Unit coverage — 7/10
Strong on stores and DTOs. Missing: `BlueskySessionService` refresh retry, `ClearskyHeartbeatService` (would have caught today's bug), `AppLockManager` timeout transitions, push routing.

### Integration coverage — 4/10
`LiveAuthenticationTests` uses real `.env` — touches login/logout but not multi-account, kill/restore, or session-after-401.

### UI coverage — 3/10
One file, no flows for add-account / list-create / lock-unlock / push-route / language-switch.

### Test quality — 6/10
Behavior-asserting, deterministic, no flakes — but no chaos injection (slow network, intermittent failure, retry storms).

### CI/build determinism — 7/10
Fixed simulator (iPhone 16 Pro / iOS 18.5), fresh-derived-data target, `translations-validate-ci` gate. Good baseline.

### Top 5 testing fixes
1. **Cover `ClearskyHeartbeatService`.** Today's iPad crash root cause shipped because there was no test. Add a suite that injects `URLProtocol`, asserts ping cadence ≈ `pingInterval` (catch unit bugs), and verifies state flips on 5xx / timeout.
2. **Token refresh on 401.** `BlueskySessionService.swift:170` — mock 401 + 200 sequence; assert old token cleared, request replayed with refreshed JWT.
3. **`AppLockManager` timeout transitions.** `AppLockManager.swift:53-77` — fake `Date` injection; assert lock on foreground after `timeoutMinutes`, instant lock when `timeoutMinutes == 0`.
4. **Push routing.** `PushNotificationCoordinator.swift:59` — feed a synthetic payload; assert `ChatStore.setAccount` and `workspaceStore.selectedTab = .chat`.
5. **Expand UI tests beyond tab smoke.** `UITests/RULYXUITests/RULYXUITests.swift` — add at minimum: add-account flow, list-create, lock/unlock with biometric stubbed, language switch persistence.

---

## 7. Internationalization (avg 5.5/10)

### Translation coverage — 7/10
All 16 bundles at key parity per `validate-translations.py`. `ar.json` has at least one orphaned key (`list.edit.metadata`).

### String API consistency — 5/10
255 `String(localized:)` calls coexist with `Text("key.path")` LocalizedStringKey usage and the bespoke `loc(...)` helper. No linter rule pins a canonical form. `InfoView.swift:497` ships a hardcoded `"Diagnostics"`.

### Plural & gender — 5/10
`_one / _other` only. Russian (нем/род/предл), Arabic (zero/one/two/few/many/other), and Polish few/many/other rules are not expressible with the current pattern.

### RTL — 6/10
`LocalizationManager.swift:41` flips `layoutDirection` for Arabic. No explicit `.flipsForRightToLeftLayoutDirection()` on directional SF Symbols; padding/margin asymmetries unaudited.

### Locale-aware formatting — 4/10
`ChatMessageBubble.swift:9-12` `DateFormatter` lacks a `.locale`. Per-call formatter allocation in scroll paths.

### Top 5 i18n fixes
1. **Localize hardcoded `"Diagnostics"`.** `InfoView.swift:497` — add `debug.diagnostics` key to all 16 bundles.
2. **Assign locale to `DateFormatter`.** `ChatMessageBubble.swift:11` — `formatter.locale = Locale(identifier: localizationManager.currentLanguage)`; today every chat timestamp ignores user locale.
3. **Pick one canonical localization API.** 255 `String(localized:)` calls coexist with `Text("key")` and `loc(...)` — recommend `Text("key")` for static strings, `loc(...)` for parameterized; enforce via lint.
4. **Tighten the translation validator to fail on orphans.** Remove `list.edit.metadata` from `ar.json`; make `validate-translations.py` exit non-zero on extra keys so CI catches drift.
5. **Audit RTL icon mirroring.** Directional SF Symbols (`chevron.right`, `arrow.forward`) in lists/buttons need `.flipsForRightToLeftLayoutDirection()` or a paired `chevron.left` for Arabic builds.

---

## Build & Crash Status

- **iPad TestFlight crash (build 37 / iPad17,2):** root-caused to `ClearskyHeartbeatService.swift:22` operator-precedence bug producing a 10-nanosecond sleep loop, which thrashed `@Published isClearskyAvailable` on the main actor and overwhelmed SwiftUI's AttributeGraph (KERN_PROTECTION_FAILURE write into libswiftCore __TEXT). Fixed today.
- **Working-tree breakage from in-progress edits:** `@MainActor` annotation on `HTTPRequestDebugStore` class broke `HTTPClient.swift:7` default parameter. Reverted to original isolation model. Build now green (`make build` → `BUILD SUCCEEDED`).
- **WIP regression introduced before this session:** `.environmentObject(appLockManager)` and `.environmentObject(iCloudAccountSync.shared)` were stripped from `RULYXApp.swift`; restoring them prevented crashes in `SettingsView` and `LockScreenView` which use `@EnvironmentObject AppLockManager`.

---

## Recommended Next-Quarter Plan

**Sprint 1 — Stability & crash hardening (P0)**
- Add `ClearskyHeartbeatService` + `AppLockManager` + `BlueskySessionService` 401-retry unit tests so the just-fixed regressions can't recur silently.
- Gate `ChatStore` / `ClearskyHeartbeatService` polling on `scenePhase`.
- Strip JWT bearer tokens from `HTTPRequestDebugStore` before persisting error JSON.

**Sprint 2 — Accessibility pass (P0)**
- Icon-only button audit + `accessibilityLabel`.
- Remove `minimumScaleFactor(0.5)`.
- Color-plus-text on every status badge / char counter.

**Sprint 3 — Architecture refactor (P1)**
- Split `ListDetailView.swift` (828 LOC) into 3 child views.
- Introduce `protocol`-based DI seams; replace `AppDependencies` god object.
- Remove `horizontalSizeClass` branches in `ProfileInspectorView`.

**Sprint 4 — Test depth (P1)**
- Expand UI tests beyond tab smoke (add-account flow, list CRUD, lock-unlock).
- Add chaos injection (latency/failure) to mock URL protocol.

**Sprint 5 — Perf & i18n polish (P2)**
- Splash skip-after-first-launch.
- Centralize `DateFormatter` with locale.
- Adopt one canonical localization API across the codebase.

---

*Generated by parallel-agent expert panel. File:line citations were verified against the working tree at synthesis time; some agent claims about scoring rationale were tightened where the underlying files said otherwise (e.g., `ModerationSplitView` is intentionally a thin wrapper per `AGENTS.md`).*
