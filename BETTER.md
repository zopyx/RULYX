# RULYX Improvement Plan

## Purpose

This document turns the July 2026 code, architecture, security, and UX audit into
an executable improvement program. It covers correctness, account isolation,
data deletion, platform configuration, CI, localization, accessibility, iPhone
and iPad UX, architecture, performance, logging, and release validation.

The plan deliberately prioritizes correctness and privacy boundaries before
visual refinement. A polished interface must not be allowed to hide stale
cross-account state, incomplete moderation results, ineffective cache deletion,
or nonfunctional platform services.

## Current Baseline

| Area | Current | Target after plan |
|---|---:|---:|
| Overall release readiness | 5/10 | 9/10 |
| Product approach | 7/10 | 9/10 |
| iPhone UX | 6/10 | 9/10 |
| iPad UX | 4/10 | 8/10 |
| Accessibility | 4/10 | 9/10 |
| Architecture | 5/10 | 8/10 |
| Security design | 8/10 | 9/10 |
| Security/privacy implementation | 6/10 | 9/10 |
| Reliability/correctness | 4/10 | 9/10 |
| Testing | 6/10 | 9/10 |
| Internationalization | 3/10 | 9/10 |
| Maintainability | 4/10 | 8/10 |
| Performance/scalability | 5/10 | 8/10 |

## Program Rules

1. Do not add major product features until Phases 1–3 pass their release gates.
2. Every account-scoped feature must document its reset and deletion behavior.
3. Every regression fix starts with a failing test where a practical test seam
   exists.
4. Do not weaken tests, lint rules, localization checks, or privacy contracts to
   obtain a green build.
5. Keep changes small enough to review. Prefer one behavioral change per commit.
6. Regenerate the Xcode project from `project.yml`; never edit the `.pbxproj`
   directly.
7. All new user-facing strings must be translated in all supported languages in
   the same change.
8. Test iPhone compact width and iPad regular and compact widths for every
   navigation or account-state change.
9. Keep production account transitions on the main actor and make the transition
   transaction explicit and observable.
10. A feature that is visible in navigation must be complete, accessible, and
    testable. Otherwise, hide it behind a development or beta gate.

## Priority and Severity Definitions

| Priority | Meaning | Required response |
|---|---|---|
| P0 | Cross-account privacy, data loss, security boundary, or release blocker | Fix before external release |
| P1 | Major correctness, broken primary workflow, or inaccessible core action | Fix before release candidate |
| P2 | Maintainability, performance, consistency, or secondary UX problem | Fix in the same milestone where possible |
| P3 | Polish or long-term structural improvement | Schedule after release gates are green |

## Delivery Overview

| Phase | Theme | Depends on | Exit condition |
|---|---|---|---|
| 0 | Baseline and change control | None | Reproducible audit baseline |
| 1 | Account isolation and cache correctness | Phase 0 | All account transitions and deletions are atomic and tested |
| 2 | Platform security and service configuration | Phase 1 | Push, iCloud, privacy shield, and pinning are correctly configured |
| 3 | Test and CI recovery | Phases 1–2 | All required CI jobs are green and deterministic |
| 4 | Moderation-data reliability and error handling | Phase 3 | No silent partial moderation results |
| 5 | Localization integrity | Phase 3 | All languages complete and quality checks enforced |
| 6 | Accessibility and iPhone UX | Phases 3 and 5 | Core workflows meet accessibility and navigation contracts |
| 7 | iPad completeness | Phases 3, 5, and 6 | Every exposed iPad workflow is functional |
| 8 | Architecture and maintainability | Phases 1–7 | Deprecated paths removed and major responsibilities separated |
| 9 | Performance, observability, and release validation | Phases 1–8 | Release gates pass on supported devices |

## Audit-to-Plan Traceability

| Audit recommendation | Plan coverage |
|---|---|
| Centralize account transitions and enforce reset ordering | BET-101 |
| Repair per-account cache deletion and filesystem-unsafe keys | BET-102, BET-103, BET-105 |
| Remove the cache metrics concurrency race | BET-104 |
| Correct entitlements, push background mode and iCloud configuration | BET-201, BET-202 |
| Guarantee the app-switcher privacy shield | BET-203 |
| Make certificate pinning and TLS behavior coherent | BET-204 |
| Remove duplicate keyboard shortcuts | BET-205 |
| Repair failing, crashing and network-dependent tests | BET-301 |
| Replace advisory architecture checks with enforceable boundaries | BET-302 |
| Make formatting, lint, translation and accessibility checks effective | BET-303, BET-304 |
| Prevent silent partial ClearSky moderation results | BET-401 |
| Distinguish loading, empty, partial and error states | BET-402, BET-605 |
| Separate thumbnail caching from application API caching | BET-403 |
| Stop reporting normal cache misses as errors | BET-404 |
| Complete and professionally review all translations | BET-501, BET-502 |
| Eliminate native localization bypasses and hardcoded strings | BET-503, BET-504 |
| Repair labels, semantics, touch targets and gesture-only actions | BET-601, BET-606 |
| Preserve tab navigation, scroll and draft state | BET-602 |
| Remove artificial splash delays | BET-603 |
| Replace unordered sibling startup tasks with explicit orchestration | BET-604 |
| Complete or hide unfinished iPad workflows | BET-701 through BET-705 |
| Decompose `LiveBlueskyClient` and oversized views/stores | BET-801, BET-803 |
| Finish dependency injection and remove force-cast facades | BET-802 |
| Route sensitive searches through protected storage | BET-804 |
| Remove sensitive public logging | BET-805 |
| Repair broken previews | BET-806 |
| Establish performance budgets and privacy-safe observability | BET-901, BET-902 |
| Perform full UX, accessibility, security and release verification | BET-903 through BET-905 |

---

## Phase 0 — Establish a Reproducible Baseline

### BET-001: Record the current verification baseline

**Priority:** P0

**Objective:** Make regressions and improvements measurable.

**Actions:**

1. Record the exact Git commit used for each verification run.
2. Run and archive results for:
   - `xcodegen generate`
   - simulator build
   - build-for-testing
   - unit tests
   - UI tests
   - `swiftformat --lint .`
   - `swiftlint`
   - translation validation
   - accessibility audit
   - contrast checks
3. Store `.xcresult` bundles as CI artifacts on failure.
4. List every failing test by test identifier and classify it as:
   - product regression
   - test isolation problem
   - environment-dependent integration test
   - obsolete expectation
5. Ensure generated `build/` and derived-data directories are excluded from
   formatter and linter discovery.

**Likely files:**

- `.github/workflows/ci.yml`
- `.swiftformat`
- `.swiftlint.yml`
- `Makefile`
- `scripts/`

**Acceptance criteria:**

- A clean checkout reproduces the same pass/fail result twice in succession.
- CI preserves useful logs and `.xcresult` data for every failed test job.
- Generated build output is not reported as source-formatting debt.

### BET-002: Freeze high-risk feature expansion

**Priority:** P1

**Objective:** Prevent new stateful features from increasing remediation cost.

**Actions:**

1. Allow security fixes, correctness fixes, test work, and contained UX repairs.
2. Defer new account-scoped stores and new top-level destinations until Phase 3.
3. Require an explicit reset/delete entry in code review for every new
   account-scoped cache or view model.

**Acceptance criteria:**

- Pull-request template includes account scope, storage classification,
  localization, and accessibility checkboxes.

---

## Phase 1 — Account Isolation and Cache Correctness

### BET-101: Make account transitions a single atomic operation

**Priority:** P0

**Problem:** `AccountStore` directly assigns `activeAccountID` from multiple
paths, bypassing the documented reset-before-publication contract.

**Primary file:**

- `Sources/Domain/Services/AccountStore.swift`

**Implementation plan:**

1. Introduce one private transition primitive, for example:
   `transitionActiveAccount(to:using:reason:)`.
2. Route every production transition through it:
   - explicit account switch
   - adding the first account
   - completing two-factor authentication
   - removing the active account
   - restoring persisted accounts
   - fallback when the preferred account disappears
3. Preserve this exact ordering:
   1. reject a no-op transition
   2. mark a transition as active
   3. clear HTTP/session/API caches
   4. clear disk model caches
   5. reset in-memory services
   6. synchronously post `.accountWillSwitch`
   7. assign `activeAccountID`
   8. persist the new selection
   9. end the transition
4. Serialize transitions. Use actor isolation or a transition generation/token
   so two rapid switches cannot interleave after an `await`.
5. Expose read-only transition state if the UI needs to disable switching and
   prevent duplicate taps.
6. Keep no-op switches side-effect free and do not post notifications.
7. Remove or restrict `setActiveAccount` so production callers cannot bypass the
   transition primitive.
8. Audit every `activeAccountID =` assignment and every production caller of
   `setActiveAccount`.

**Tests:**

- Adding the first account resets state before publishing its ID.
- Completing 2FA uses the same transition.
- Removing the active account transitions to the fallback account atomically.
- Removing the final account clears all account-scoped state.
- Removing a non-active account does not reset the active account.
- A no-op switch emits no notification.
- Notification is delivered before observers see the new ID.
- Rapid A→B→C switches finish with C and no B data.
- A failed transition leaves a defined state and presents a recoverable error.
- iPhone and iPad visible view models refetch exactly once for the final account.

**Acceptance criteria:**

- Only the transition primitive can assign a new production `activeAccountID`.
- Reset ordering is asserted in tests rather than only documented.
- No stale account-specific counters, chat content, timeline content, search
  content, or relationship data appears after a switch.

### BET-102: Redesign API cache ownership and per-account deletion

**Priority:** P0

**Problem:** Cache files are named with a hash of `accountDID + URL`, while
per-account deletion searches for a hash of only the DID. Deletion therefore
cannot find the files.

**Primary files:**

- `Sources/Domain/Services/BlueskyAPICache.swift`
- `Tests/RULYXTests/BlueskyAPICacheTests.swift` (new if absent)

**Implementation options:**

Choose one explicit ownership model:

1. **Preferred:** One hashed directory per account and one hashed filename per
   request URL.
2. Store a metadata index mapping account hashes to cache filenames.
3. Store account identity in a cache-file envelope and scan metadata during
   deletion.

The directory model is simplest and makes deletion auditable:

```text
BlueskyAPICache/
  <SHA256 account DID>/
    <SHA256 normalized URL>.cache
```

**Actions:**

1. Normalize request identity consistently before hashing.
2. Never place raw handles, DIDs, tokens, or request URLs in filenames.
3. Make per-account deletion remove the entire hashed directory.
4. Make last-account removal clear the cache root.
5. Add a version marker and migrate or safely discard the old cache layout.
6. Treat missing files/directories as successful no-op deletion.
7. Ensure file protection and backup-exclusion attributes remain correct.

**Tests:**

- Two accounts caching the same URL receive isolated files.
- Clearing account A cannot remove account B.
- Clearing account A removes all of A.
- A DID containing colons or other reserved characters never becomes a path.
- Last-account removal empties the root.
- Missing-file deletion produces no error log.
- Legacy-layout migration is deterministic.

**Acceptance criteria:**

- Filesystem tests prove per-account deletion.
- No account identifier appears in the on-disk path.
- Account-removal tests inspect disk state, not just mock invocations.

### BET-103: Make Dashboard and Relationship cache keys filesystem-safe

**Priority:** P0

**Primary files:**

- `Sources/Domain/Services/DashboardCache.swift`
- `Sources/Domain/Services/RelationshipCache.swift`
- `Tests/RULYXTests/RelationshipCacheTests.swift`
- corresponding dashboard-cache tests

**Actions:**

1. Replace raw key interpolation with a stable hash.
2. Keep cache type and schema version visible in the filename or parent path.
3. Store the logical key in protected file contents only if required for
   debugging or validation.
4. Treat a missing cache entry as a normal miss rather than an error.
5. Add migration or cleanup for filenames created by the previous scheme.

**Acceptance criteria:**

- DIDs, handles, empty strings, Unicode, and very long keys are safe.
- Normal cache misses do not pollute error logs.
- Clear and load behavior is covered by real temporary-directory tests.

### BET-104: Eliminate the cache-metrics data race

**Priority:** P0

**Problem:** Mutable counters are wrapped in `@unchecked Sendable` and accessed
outside actor isolation.

**Primary file:**

- `Sources/Domain/Services/BlueskyAPICache.swift`

**Actions:**

1. Move counters into the cache actor or a dedicated `CacheMetrics` actor.
2. Return an immutable `Sendable` snapshot for UI presentation.
3. Make reset actor-isolated.
4. Remove `@unchecked Sendable`.
5. Avoid synchronous nonisolated reads of mutable state.

**Tests:**

- Concurrent hit/miss recording reaches the expected exact totals.
- Reset cannot race with reads.
- Thread Sanitizer reports no metric-store race.

### BET-105: Complete account removal and “Delete All Data” semantics

**Priority:** P0

**Actions:**

1. Create a registry or explicit checklist of every account-scoped persistence
   component.
2. Ensure removal clears:
   - Keychain credentials
   - persisted sessions
   - API cache
   - dashboard cache
   - relationship cache
   - thread cache
   - chat cache where account-scoped
   - any future account-scoped stores
3. Define the UI action precisely:
   - “Clear caches” clears reproducible cache data.
   - “Delete moderation history” clears audit/history data.
   - “Delete all app data” clears every app-created store, preference, credential,
     account, export temporary file, and cache.
4. Avoid naming a partial operation “Delete All Data.”
5. Require destructive confirmation that lists the categories being deleted.

**Tests:**

- Seed every store, remove an account, then verify disk and Keychain state.
- Seed global stores and confirm they remain during an account switch.
- Full app-data deletion leaves no app-owned sensitive file behind.

**Phase 1 release gate:**

- All account transition and deletion tests pass under normal and rapid-switch
  conditions.
- No raw DID is used as a cache path component.
- Thread Sanitizer passes the account/cache test subset.

---

## Phase 2 — Platform Security and Service Configuration

### BET-201: Activate and verify application entitlements

**Priority:** P0

**Primary files:**

- `project.yml`
- `Sources/App/RULYX.entitlements`
- generated `RULYX.xcodeproj`

**Actions:**

1. Configure `CODE_SIGN_ENTITLEMENTS` in `project.yml`.
2. Regenerate the Xcode project.
3. Verify the built app’s signed entitlements using `codesign -d --entitlements`.
4. Configure APNs entitlement values appropriately for Debug and Release.
5. Add the iCloud key-value-store entitlement if iCloud account sync remains a
   supported feature.
6. If iCloud sync is not intended for the next release, disable and hide it
   rather than initializing a service without valid entitlement support.

**Acceptance criteria:**

- Built Debug and Release products contain the intended entitlements.
- No runtime “Unable to find entitlement for KVS store” message.
- Entitlement verification runs in CI or a release script.

### BET-202: Correct background notification configuration

**Priority:** P0

**Primary files:**

- `project.yml`
- `Sources/App/Info.plist`
- `Sources/App/BlueskyAppDelegate.swift`
- push-notification services and tests

**Actions:**

1. Add `remote-notification` to `UIBackgroundModes` if background delivery is
   required.
2. Confirm `fetch` is still needed; remove unused modes.
3. Verify registration, token refresh, foreground delivery, notification tap,
   and background content refresh on a physical device.
4. Ensure completion handlers are called exactly once on every code path.
5. Add structured diagnostic events without logging tokens or payload bodies.

**Acceptance criteria:**

- Runtime emits no missing-background-mode warning.
- Physical-device tests confirm expected notification behavior.

### BET-203: Make the privacy shield synchronous and testable

**Priority:** P0

**Primary file:**

- `Sources/App/RULYXApp.swift`

**Actions:**

1. Set `showPrivacyShield` synchronously in the main-actor background callback.
2. Remove unnecessary `DispatchQueue.main.async`.
3. Keep the shield opaque, independent of app-lock configuration.
4. Remove it only after the app becomes active.
5. Add a UI/lifecycle test using a non-sensitive marker behind the shield.

**Acceptance criteria:**

- The shield is present before the background event handler returns.
- App-switcher snapshots cannot contain account content.

### BET-204: Define a coherent TLS and certificate-pinning policy

**Priority:** P1

**Problem:** Some request paths use pinned clients while other service paths use
an unpinned executor. Static pins also lack a safe rotation strategy.

**Primary files:**

- `Sources/Domain/Services/HTTPClient.swift`
- `Sources/Domain/Services/BlueskyRequestExecutor.swift`
- `Sources/Domain/Services/AppDependencies` or equivalent construction code
- `Sources/Domain/Services/LiveBlueskyClient.swift`

**Actions:**

1. Inventory every `URLSession` and request executor.
2. Choose one policy:
   - standard platform TLS everywhere; or
   - pin only owned, stable first-party hosts with documented operational support.
3. Do not pin arbitrary user-selected PDS hosts.
4. If pinning is retained:
   - ship primary and backup pins
   - document rotation and emergency recovery
   - centralize trust handling
   - add expiry/rotation monitoring
   - ensure tests use an injectable trust evaluator
5. Ensure tests do not accidentally contact live `bsky.social` because the mock
   session and production trust delegate disagree.

**Acceptance criteria:**

- Every network path has an intentional documented trust policy.
- Test traffic is deterministic and never escapes to live services.
- Pin rotation can occur without an emergency app release race.

### BET-205: Remove the duplicate Settings keyboard shortcut

**Priority:** P2

**Primary file:**

- `Sources/App/RULYXApp.swift`

**Actions:**

1. Do not register Command-comma when the system already provides Settings.
2. Retain only unique shortcuts.
3. Add a shortcut registry uniqueness test.

**Phase 2 release gate:**

- No entitlement, background mode, KVS, or duplicate-shortcut warnings at launch.
- Physical-device push smoke test passes.
- Privacy shield behavior is verified.

---

## Phase 3 — Test and CI Recovery

### BET-301: Repair unit-test isolation and failure behavior

**Priority:** P0

**Problem:** The suite currently fails, restarts processes, and includes tests
that crash after an assertion failure.

**Primary files:**

- `Tests/RULYXTests/LiveBlueskyClientTests.swift`
- `Tests/RULYXTests/BlueskySessionServiceTests.swift`
- `Tests/RULYXTests/AutoBlockBackServiceTests.swift`
- `Tests/RULYXTests/ClearskyHeartbeatServiceTests.swift`
- `Tests/TestUtilities/`

**Actions:**

1. Replace “assert count then index” with `XCTUnwrap`, guarded access, or equality
   against an expected collection.
2. Reset all global URL protocol handlers, stores, defaults suites, Keychain test
   items, notification observers, and static state in `tearDown`.
3. Give each test a unique temporary directory and `UserDefaults` suite.
4. Inject clocks, sessions, caches, and trust evaluation.
5. Prohibit live networking in unit-test configurations.
6. Split live credential tests into a separately invoked integration-test plan.
7. Correct mock URL matching for encoded query parameters and AT URIs.
8. Ensure test order randomization does not alter results.

**Acceptance criteria:**

- Unit tests pass three consecutive runs with randomized ordering.
- No test process exits unexpectedly.
- Unit tests pass with network access disabled.

### BET-302: Turn architecture tests into real guardrails

**Priority:** P1

**Primary file:**

- `Tests/RULYXTests/ArchitectureEnforcementTests.swift`

**Actions:**

1. Replace unconditional `XCTAssertTrue(true)` branches with actual failures.
2. Define allowed dependency directions:

```text
Views -> ViewModels/Stores -> Domain protocols -> Services
```

3. Enforce:
   - no direct concrete service construction in views
   - no deprecated client facade in new code
   - no native Apple localization API
   - no production `setActiveAccount`
   - no direct sensitive query storage in standard `UserDefaults`
   - no public logging of prohibited identifiers
4. Create a small, explicit legacy allowlist with removal deadlines.
5. Fail when the allowlist grows.

**Acceptance criteria:**

- Introducing a known boundary violation makes the test fail.
- Allowlisted debt decreases over time.

### BET-303: Make lint, formatting, translations, and accessibility required

**Priority:** P1

**Primary files:**

- `.github/workflows/ci.yml`
- `.swiftformat`
- `.swiftlint.yml`
- localization and accessibility scripts

**Actions:**

1. Remove inappropriate `continue-on-error` behavior from release-critical jobs.
2. Run formatter lint, SwiftLint, translation validation, build and unit tests as
   independent required checks.
3. Keep accessibility scanning advisory until false positives are classified,
   then promote verified rules to required checks.
4. Add script unit tests so parser changes cannot silently reduce coverage.
5. Prevent validation scripts from mutating the checkout during CI unless a diff
   is intentionally being verified.

**Acceptance criteria:**

- The default branch cannot merge with any required check failing.
- Each failed check provides a concise actionable report.

### BET-304: Reduce existing lint debt without hiding it

**Priority:** P2

**Actions:**

1. Apply SwiftFormat to focused batches.
2. Fix hard SwiftLint errors first.
3. Split long functions and types based on responsibility rather than adding
   blanket exclusions.
4. Use temporary path-specific exceptions only with an issue ID and expiry.

**Phase 3 release gate:**

- Required CI is green on two consecutive clean runs.
- Unit tests make no external network requests.
- Test crashes and process restarts are eliminated.

---

## Phase 4 — Moderation Data Reliability and Error Handling

### BET-401: Make ClearSky pagination complete or explicitly incomplete

**Priority:** P0

**Primary files:**

- `Sources/Domain/Services/LiveBlueskyClient.swift`
- relationship/list view models
- ClearSky-related tests

**Actions:**

1. Stop converting later-page failures into empty pages.
2. Return a typed result that distinguishes:
   - complete data
   - temporarily unavailable
   - partial data with recoverable continuation
   - server-enforced truncation
3. Do not cache a partial result as complete.
4. Retry transient page failures using bounded exponential backoff and jitter.
5. Preserve a cursor/checkpoint when retrying is safe.
6. Surface partial status in the UI if partial display is intentionally allowed.
7. Replace the silent 5,000-record cap with:
   - complete pagination, or
   - an explicit documented limit presented to the user.
8. Keep dashboard and relationship-detail counts derived from the same completed
   dataset.

**Tests:**

- Failure on page 2 does not produce a completed one-page result.
- Retry succeeds without duplicating actors.
- Cancellation stops work without caching.
- Duplicate records across pages are deduplicated.
- Very large lists behave according to the documented limit policy.
- Dashboard and detail counts match.

### BET-402: Use structured state for loading, empty, partial, and error results

**Priority:** P1

**Primary areas:**

- `NewConversationSheet`
- profile windows
- search results
- moderation relationship screens

**Actions:**

1. Replace silent `catch { results = [] }` patterns with explicit state enums.
2. Never make a network error indistinguishable from “no results.”
3. Do not fabricate a minimal profile when profile loading fails.
4. Provide retry actions and concise localized explanations.
5. Preserve the prior successful result while refresh errors are recoverable.
6. Normalize errors through `AppError`.

**Acceptance criteria:**

- Empty, offline, unauthorized, rate-limited, partial, and server-error states
  render differently.
- Every failed primary operation has an accessible recovery action.

### BET-403: Separate media caching from global API caching

**Priority:** P1

**Primary files:**

- `Sources/Features/Lists/Profile/MediaBrowserViewModel.swift`
- thumbnail/networking services
- `Sources/App/RULYXApp.swift`

**Actions:**

1. Stop overwriting `URLCache.shared` from a feature view model.
2. Give thumbnail fetching a dedicated `URLSession` and `URLCache`.
3. Choose cache sizes based on measured device memory and storage impact.
4. Apply memory-pressure handling.
5. Keep public CDN thumbnails separate from viewer-relative API responses.
6. Document eviction and account-switch behavior.

**Acceptance criteria:**

- Opening the media browser cannot change global API cache policy.
- Cache usage remains within a measured budget on older supported devices.

### BET-404: Make normal cache misses quiet and actionable failures visible

**Priority:** P2

**Actions:**

1. Log expected “file not found” as a cache miss metric, not an error.
2. Log permission, decoding, corruption, and deletion failures at appropriate
   non-public privacy levels.
3. Include store category and operation, but not raw keys.

**Phase 4 release gate:**

- Moderation counts cannot silently reflect a partial request.
- Network errors are visually distinct from legitimate empty states.
- Media browsing does not mutate the shared application cache.

---

## Phase 5 — Localization Integrity

### BET-501: Restore complete key and placeholder parity

**Priority:** P0

**Primary files:**

- `Sources/Shared/Localizations/*.json`
- `Sources/Shared/Localizations/Localizable.xcstrings`
- `Tests/RULYXTests/LocalizationCompletenessTests.swift`
- `scripts/validate-translations.py`

**Actions:**

1. Add every missing English key to all 15 non-English bundles.
2. Preserve placeholder contracts such as `{n}` in every translation.
3. Synchronize or remove `Localizable.xcstrings` if it is not the runtime source
   of truth. Do not keep two drifting localization authorities.
4. Validate duplicate keys, invalid JSON, unexpected markup, empty values and
   unsupported placeholders.
5. Fail CI on any parity or placeholder mismatch.

**Acceptance criteria:**

- All language bundles have identical key sets.
- Placeholder validation passes.
- The runtime and validation source of truth are the same.

### BET-502: Replace pseudo and untranslated content with native translations

**Priority:** P1

**Actions:**

1. Inventory values containing language markers such as `(AR)`, `(PL)` or `[ja]`.
2. Identify identical-to-English values, excluding proper nouns and intentional
   technical terms.
3. Have translations reviewed by native speakers or a professional localization
   workflow.
4. Add reviewer and review-date metadata outside runtime JSON if useful.
5. Test Arabic layouts manually in right-to-left mode.
6. Review truncation in German, French, Russian and other expansion-heavy
   languages.
7. Review plural and relative-date grammar per language.

**Acceptance criteria:**

- No pseudo-translation markers remain.
- Identical-to-English exceptions are explicitly allowlisted and justified.
- Key workflows receive human linguistic review.

### BET-503: Enforce the custom localization API

**Priority:** P1

**Actions:**

1. Replace native/localized-key calls with:
   - `loc("key")`
   - `String.localized`
   - `Text(loc:)`
   - custom localized view modifiers
2. Replace hardcoded production English strings.
3. Add a source scanner that rejects:
   - `String(localized:)`
   - `LocalizedStringResource`
   - user-visible `Text("literal")` outside approved cases
   - `Button("key")`, `Label("key")`, and `Section("key")` when they bypass
     `loc`
4. Exclude previews and debugging only through narrow documented rules.

**Acceptance criteria:**

- Changing the in-app language updates every visible production screen without
  changing the device language.

### BET-504: Add localization UI coverage

**Priority:** P2

**Actions:**

1. Add screenshot/UI tests for English, German, Arabic and one CJK language.
2. Exercise Dynamic Type simultaneously with long translations.
3. Verify navigation titles, toolbar labels, empty states and destructive
   confirmations.

**Phase 5 release gate:**

- Translation validation is green.
- No placeholder markers or missing keys remain.
- RTL and long-language UI smoke tests pass.

---

## Phase 6 — Accessibility and iPhone UX

### BET-601: Repair core action semantics and target sizes

**Priority:** P0

**Primary files:**

- `Sources/Shared/Components/Posts/PostActionBar.swift`
- `Sources/Features/Notifications/NotificationRow.swift`
- `Sources/Features/Lists/UserSearchSheet.swift`
- `Sources/Features/Chat/NewConversationSheet.swift`
- other results from `scripts/audit-accessibility.py`

**Actions:**

1. Give reply, repost, like, quote, share and menu controls localized labels and
   state-aware hints.
2. Announce selected/toggled state with appropriate accessibility traits or
   values.
3. Ensure a minimum 44×44pt hit target without unnecessarily enlarging the
   visible icon.
4. Replace tappable rows implemented only with `onTapGesture` with `Button` or
   `NavigationLink`.
5. Where double-tap behavior remains, provide a visible and accessible
   equivalent action.
6. Combine avatar/name/handle metadata into logical reading groups.
7. Validate focus order and avoid duplicate announcements.

**Tests:**

- Accessibility identifiers and localized labels exist for primary actions.
- UI tests invoke actions through accessibility rather than coordinates.
- VoiceOver manual pass covers timeline, profile, lists, account switch, chat and
  notifications.

### BET-602: Replace the custom bottom navigation with state-preserving navigation

**Priority:** P1

**Primary file:**

- `Sources/App/RootView.swift`

**Preferred implementation:**

1. Use a native `TabView` with a stable selection.
2. Keep a persistent `NavigationStack` and path for each top-level tab.
3. Preserve scroll positions and draft state when switching tabs.
4. Keep the number of primary tabs understandable on narrow phones.
5. Place secondary destinations in a More/System area if necessary.
6. Make account switching a normal labeled button or menu.
7. Retain double-tap shortcuts only as optional enhancements with visible
   alternatives.

**Tests:**

- Navigate deeply in a tab, switch away, return, and retain the path.
- Preserve compose/search drafts and scroll position.
- Account switching is reachable with VoiceOver and Switch Control.
- Compact widths do not truncate every tab label.

### BET-603: Remove the recurring artificial launch delay

**Priority:** P1

**Primary file:**

- `Sources/App/RULYXApp.swift`

**Actions:**

1. Let the system launch screen cover startup.
2. Show an in-app loading state only while essential initialization is genuinely
   incomplete.
3. Remove fixed sleeps and repeat-launch splash delays.
4. Measure cold and warm launch using signposts and XCTest metrics.

**Acceptance criteria:**

- No fixed launch delay.
- Users can interact as soon as required state is ready.

### BET-604: Make startup tasks explicit and ordered

**Priority:** P0

**Primary files:**

- `Sources/App/RULYXApp.swift`
- startup/service coordinator files

**Actions:**

1. Replace sibling `.task` assumptions with one startup coordinator.
2. Encode dependencies:

```text
restore accounts/session
  -> establish active account
  -> start account-scoped chat/timeline work
  -> register/refresh push state
  -> start independent health monitoring
```

3. Run genuinely independent work concurrently only after prerequisites exist.
4. Make startup idempotent.
5. Cancel account-scoped tasks on account transition.
6. Represent startup state with an enum rather than several booleans.

**Tests:**

- Delayed session restoration does not start chat with a preview/wrong account.
- Re-entering the scene does not duplicate observers or background tasks.
- Account switch cancels old startup-derived tasks.

### BET-605: Improve feedback and recovery

**Priority:** P1

**Actions:**

1. Distinguish empty results from failure.
2. Show progress only where the wait is perceptible.
3. Use actionable retry buttons.
4. Preserve input after recoverable errors.
5. Avoid success banners before asynchronous deletion actually completes.
6. Use confirmation dialogs for destructive bulk operations.

### BET-606: Validate Dynamic Type, contrast and motion comprehensively

**Priority:** P1

**Actions:**

1. Audit all primary screens at accessibility text sizes.
2. Avoid fixed-height containers around user text.
3. Verify semantic colors in light, dark and increased-contrast modes.
4. Expand contrast automation beyond the current four checks.
5. Ensure Reduce Motion removes decorative movement without suppressing essential
   state changes.
6. Test Bold Text, Button Shapes and Differentiate Without Color.

**Phase 6 release gate:**

- Primary workflows are operable with VoiceOver without gesture-only actions.
- Navigation preserves state.
- No fixed repeat-launch delay remains.
- Accessibility Inspector reports no critical issue in the release workflow set.

---

## Phase 7 — Complete the iPad Experience

### BET-701: Implement or hide internal-list creation

**Priority:** P0

**Primary file:**

- `Sources/App/iPad/iPadListsView.swift`

**Actions:**

1. Replace constant bindings with real draft state.
2. Validate the name and selected color.
3. Persist through `InternalListStore`.
4. Select and display the newly created list after saving.
5. Present recoverable errors.
6. Add Cancel and Save using the toolbar-role conventions.

**Acceptance criteria:**

- A list created on iPad appears immediately and persists after relaunch.
- Save is disabled for invalid input.

### BET-702: Finish internal-list selection and management

**Priority:** P1

**Actions:**

1. Give internal-list rows stable selection values.
2. Render members in the detail column.
3. Implement rename, delete, member removal and drag/drop where promised.
4. Ensure destructive actions request confirmation.
5. Implement sidebar editing only if actual move/delete operations are supported;
   otherwise remove `EditButton`.

### BET-703: Complete or beta-gate mentions search

**Priority:** P1

**Primary file:**

- `Sources/App/iPad/iPadMentionsSearchWrapper.swift`

**Actions:**

1. Implement the full preferred-search-account flow and results state, or
2. Remove the destination from production navigation until complete.
3. Do not expose a dead-end placeholder as a primary sidebar destination.

### BET-704: Centralize iPad dependency and account-change behavior

**Priority:** P1

**Primary files:**

- `Sources/App/iPad/iPadRootView.swift`
- iPad feature wrappers
- application dependency environment

**Actions:**

1. Remove duplicated onboarding and dependency-injection setup.
2. Ensure iPad view models independently obey account reset/refetch contracts.
3. Share feature models with iPhone where behavior is identical.
4. Keep only layout/navigation adaptation in iPad-specific wrappers.
5. Verify compact iPad width falls back cleanly to phone navigation.

### BET-705: Add iPad workflow UI tests

**Priority:** P1

**Coverage:**

- sidebar navigation
- list creation and deletion
- list member inspection
- profile window
- command palette
- account switching
- split-view column behavior
- compact/regular size changes
- keyboard shortcuts and pointer interactions

**Phase 7 release gate:**

- Every production sidebar item opens a complete workflow.
- Internal lists are fully usable.
- iPad account switching passes the same isolation tests as iPhone.

---

## Phase 8 — Architecture and Maintainability

### BET-801: Decompose `LiveBlueskyClient`

**Priority:** P1

**Problem:** A 2,500+ line type implementing 11 protocols creates excessive
coupling and makes networking, caching, trust and test behavior hard to isolate.

**Target structure:**

```text
SessionService
ProfileService
ListService
RelationshipService
FeedService
ModerationService
ClearSkyService
ChatService
RequestExecutor
CacheCoordinator
```

**Actions:**

1. Keep protocols small and capability-oriented.
2. Move endpoint decoding and pagination into the owning service.
3. Share authentication and retry behavior through `BlueskyRequestExecutor`.
4. Avoid replacing one god object with a god service container.
5. Migrate one feature domain at a time.
6. Keep compatibility adapters temporary and mark their removal milestone.

**Acceptance criteria:**

- No production view requires `LiveBlueskyClient`.
- Each service can be tested with an injected executor.
- `LiveBlueskyClient` is removed or reduced to a thin facade with no independent
  state.

### BET-802: Finish dependency-injection migration

**Priority:** P1

**Primary files:**

- `Sources/App/AppEnvironment.swift`
- `Sources/Domain/Services/BlueskyServiceContainer.swift`
- `Sources/Domain/Services/BlueskyServiceContainerWrapper.swift`

**Actions:**

1. Decide whether `AppEnvironment` or explicit environment values are the final
   application boundary.
2. Stop injecting both the consolidated environment and all legacy objects.
3. Replace the deprecated concrete `blueskyClient` force cast.
4. Inject only the narrow capabilities each view/view model needs.
5. Make invalid construction a compile-time error rather than a force-cast crash.
6. Update previews to use the same supported dependency boundary.

**Acceptance criteria:**

- No `as! LiveBlueskyClient` dependency bridge remains.
- Deprecated facade usage reaches zero.
- Primary previews render without missing environment-object crashes.

### BET-803: Split oversized views into state, orchestration and presentation

**Priority:** P2

**Initial targets:**

- `BlueskyProfileView`
- `RelationshipsView`
- `ListDetailView`
- `UserPostsView`
- `ChatStore`

**Actions:**

1. Keep data loading and mutations in focused observable models/stores.
2. Extract reusable presentational sections with explicit inputs and actions.
3. Use state enums for mutually exclusive loading/error/content states.
4. Avoid extensions that merely hide a giant type across multiple files without
   reducing responsibility.
5. Add focused previews and snapshot tests for extracted states.

**Acceptance criteria:**

- No new SwiftLint type/file-length suppression is needed.
- Extracted components can be previewed and tested independently.

### BET-804: Formalize storage classification

**Priority:** P1

**Actions:**

1. Document every persisted field as:
   - secret
   - sensitive non-secret
   - account-scoped cache
   - global preference
   - public reproducible media
   - debug-only diagnostic
2. Route secrets only to Keychain.
3. Route sensitive payloads only to `ProtectedDataStore`.
4. Route non-sensitive preferences to `UserDefaults`.
5. Move search history out of direct standard `UserDefaults` usage in
   `CustomSearchViewModel`.
6. Add architecture tests against prohibited storage calls.

### BET-805: Fix logging privacy violations

**Priority:** P0

**Actions:**

1. Audit every `privacy: .public`.
2. Remove public logging for handles, DIDs where sensitive in context, search
   queries, list names, conversation identifiers, record URIs, cache keys and
   response bodies.
3. Prefer counts, operation names and normalized error categories.
4. Keep permitted error descriptions public only where they cannot embed
   prohibited input; otherwise mark them private.
5. Add a source-level CI rule with a narrow allowlist.
6. Review HTTP debug export/share behavior and retention.

**Acceptance criteria:**

- A `log show` review after exercising the app contains no prohibited user data.

### BET-806: Repair previews and developer ergonomics

**Priority:** P2

**Actions:**

1. Provide one supported preview dependency factory.
2. Ensure Settings and other dependency-heavy previews inject all required
   services.
3. Keep preview data deterministic and fully offline.
4. Add preview compilation to a lightweight verification target where practical.

**Phase 8 release gate:**

- Deprecated client facade usage is zero or has a short, explicit final removal
  list.
- Major services and views are below agreed responsibility/size thresholds.
- Storage and logging policies are enforced automatically.

---

## Phase 9 — Performance, Observability, and Release Validation

### BET-901: Establish performance budgets

**Priority:** P1

**Budgets to define and measure:**

- cold and warm launch time
- account-switch completion time
- timeline first-content time
- large-list pagination time
- peak memory during media browsing
- disk cache usage
- scrolling hitch rate
- background refresh duration

**Actions:**

1. Use `XCTMetric`, Instruments and existing `AppLogger.performance` signposts.
2. Test on an older supported iPhone and a current iPad, not only a high-end
   simulator.
3. Fail performance tests only after stable baselines and tolerances are known.
4. Track regressions per release.

### BET-902: Make observability privacy-safe and useful

**Priority:** P2

**Actions:**

1. Record cache hit/miss counts via actor-safe snapshots.
2. Record pagination completion versus partial/failure state.
3. Record account-switch phase durations without account identifiers.
4. Separate debug logs from user-visible diagnostics.
5. Provide a redacted support report users can review before sharing.

### BET-903: Run a full accessibility and UX acceptance pass

**Priority:** P0

**Device/settings matrix:**

- compact iPhone
- large iPhone
- regular-width iPad
- compact-width iPad multitasking
- portrait and landscape
- light and dark mode
- increased contrast
- accessibility text size
- VoiceOver
- Switch Control smoke test
- Reduce Motion
- Arabic RTL
- German long strings

**Core workflows:**

- add/remove/switch accounts
- set preferred search account
- inspect a profile
- block/mute/follow
- create and modify lists
- bulk moderation
- timeline actions
- notifications
- chat
- export/import
- app lock and background privacy shield

### BET-904: Conduct focused security verification

**Priority:** P0

**Checklist:**

- Verify signed entitlements.
- Inspect Keychain accessibility attributes.
- Inspect file-protection and backup-exclusion attributes.
- Confirm account removal deletes per-DID artifacts.
- Confirm app-wide deletion semantics.
- Confirm JWT URL redaction.
- Confirm no sensitive public logs.
- Confirm custom PDS authentication uses trusted DID resolution and HTTPS.
- Confirm export temporary files are protected and deleted.
- Confirm app-switcher snapshots are opaque.
- Confirm no unit test or production fallback sends credentials to a
  handle-derived host.

### BET-905: Final release gates

A release candidate is acceptable only when all conditions are true:

- [ ] Clean `xcodegen generate`
- [ ] Simulator build succeeds
- [ ] Build-for-testing succeeds
- [ ] Unit tests pass three consecutive runs
- [ ] UI tests pass on iPhone and iPad
- [ ] SwiftFormat lint passes
- [ ] SwiftLint passes without new blanket exclusions
- [ ] Translation validation passes for all 16 languages
- [ ] Accessibility critical-path audit passes
- [ ] Contrast validation covers all semantic colors used by primary actions
- [ ] No runtime entitlement, KVS, background-mode or shortcut-conflict warnings
- [ ] Account-switch and account-removal isolation tests pass
- [ ] ClearSky partial-result tests pass
- [ ] Physical-device push smoke test passes
- [ ] Privacy/security checklist passes
- [ ] Performance remains inside documented budgets
- [ ] Known limitations are accurately described in product copy

---

## Cross-Cutting Test Matrix

| Concern | Unit | Integration | UI | Manual/device |
|---|---|---|---|---|
| Account transition ordering | Required | Required | Required | Smoke |
| Per-account cache deletion | Required with real temp filesystem | Required | Optional | Inspect app container |
| Push notifications | Coordinator tests | Mock APNs routing | Notification tap | Physical device required |
| iCloud KVS | Store tests | Entitled build | Settings toggle | Physical device/account |
| ClearSky pagination | Required | Stub server | Partial/error state | Network-condition test |
| Localization | Key/placeholder tests | Bundle load | Screenshots | Native review |
| Accessibility | Label/state checks | — | Accessibility-driven UI tests | VoiceOver required |
| Navigation persistence | State tests | — | Required | Orientation/multitasking |
| Privacy shield | State ordering | Scene lifecycle | Snapshot assertion | App switcher |
| Logging hygiene | Source policy tests | Redacted logger | — | `log show` inspection |
| Performance | Algorithms/cache | Service timing | XCT metrics | Instruments |

## Recommended Commit Sequence

1. `test: add account transition invariant coverage`
2. `fix: centralize and serialize active account transitions`
3. `test: cover per-account cache deletion on disk`
4. `fix: isolate cache files by hashed account directory`
5. `fix: make dashboard and relationship cache keys filesystem-safe`
6. `fix: actor-isolate cache metrics`
7. `build: configure app entitlements and background notification mode`
8. `fix: activate privacy shield synchronously`
9. `test: isolate network clients and remove unit-test crashes`
10. `ci: enforce deterministic tests lint and translation validation`
11. `fix: preserve complete ClearSky pagination semantics`
12. `fix: separate thumbnail and API URL caches`
13. `i18n: restore translation parity and native content`
14. `a11y: repair primary action labels semantics and targets`
15. `refactor: adopt state-preserving phone tab navigation`
16. `feat: complete internal list workflows on iPad`
17. `refactor: decompose Bluesky services by capability`
18. `refactor: remove deprecated service-container facade`
19. `privacy: enforce protected storage and private logging`
20. `test: add release accessibility security and performance gates`

## Risk Management

| Risk | Mitigation |
|---|---|
| Account transition refactor breaks login or restoration | Add characterization tests before moving assignments |
| Cache layout migration leaves old sensitive files | Version cache root and explicitly remove legacy paths after successful migration |
| Strict CI exposes a large backlog | Fix P0/P1 checks first; use narrow expiring allowlists rather than disabling checks |
| Service decomposition causes a long-lived hybrid architecture | Migrate one capability end-to-end and delete its legacy path immediately |
| Translation work becomes stale during remediation | Freeze new keys briefly, then require all-language updates atomically |
| Native TabView changes visual identity | Preserve styling through supported tab APIs, but keep system semantics |
| Pin rotation causes outages | Ship backup pins or remove unsupported pinning in favor of platform TLS |
| iPad repair duplicates phone logic | Share feature state and mutations; specialize only layout/navigation |

## Definition of Done for Each Work Item

A work item is complete only when:

1. The implementation addresses the root cause, not only the observed symptom.
2. Relevant unit or UI regression tests exist and pass.
3. Account-switch and account-removal implications are documented.
4. Storage and log privacy have been reviewed.
5. New strings exist in all 16 language files with native translations.
6. VoiceOver labels, traits, focus and target size are verified for changed UI.
7. iPhone and iPad behavior are verified where the feature appears on both.
8. SwiftFormat and SwiftLint pass for touched files.
9. No unrelated warnings or blanket suppressions are introduced.
10. Documentation and product claims match the delivered behavior.

## Completion Reporting Template

Every completed task should include:

| Area | Change | Impact |
|---|---|---|
| Files modified | Exact file list | What changed and why |
| Tests | Commands and results | What behavior is now protected |
| Account scope | Reset/deletion behavior | Whether account isolation changed |
| UX/accessibility | User-visible behavior | iPhone/iPad and assistive-technology impact |
| Localization | Keys/languages changed | Translation and RTL impact |
| Remaining risk | Known follow-up | Why it is safe to defer |
