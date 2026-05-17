# HIGH/Critical Issue Remediation Plan

Generated: 2026-05-12 — 1 CRITICAL + 6 HIGH: Maintainability + 2 HIGH: Security + 2 HIGH: Test Coverage + 1 HIGH: Localization

---

## Execution Order (Recommended)

Issues are ordered to minimize rework — lint/tooling fixes first, then simple localized fixes, then refactors, then tests.

---

## Phase 1: Tooling & Safety Net

### 1.1 CRITICAL — PinningDelegate Accepts Any Certificate

**File:** `Sources/Domain/Services/BlueskyRequestExecutor.swift:115-131`
**Risk:** MITM against all bsky.social API traffic (JWT tokens, moderation data)

**Plan:**
1. Extract `SecKey` from `serverTrust` for bsky.social's certificate chain
2. Compare against a hardcoded set of SPKI (Subject Public Key Info) hashes
3. Fall back to `.cancelAuthenticationChallenge` on mismatch
4. Add a test that verifies known-good and known-bad fingerprints
5. Document rotation process for when bsky.social rotates their certs

**Effort:** 1–2h · **Dependencies:** None

### 1.2 HIGH — SwiftLint Disables 32 Critical Rules

**File:** `.swiftlint.yml:8-32`
**Risk:** Force unwraps, TODOs, long functions, and complexity invisible to automated review

**Plan:**
1. Re-enable `force_unwrapping`, `todo`, `force_cast` immediately (highest ROI)
2. Re-enable `file_length`, `function_body_length`, `type_body_length`, `line_length` with reasonable threshold violations set to `error`
3. Run `swiftformat --lint . && swiftlint` and fix all violations
4. Audit remaining disabled rules individually — keep only those with legitimate reasons
5. Add CI step that runs swiftlint and fails on new violations

**Effort:** 2–3h · **Dependencies:** None (do first to catch regressions in later phases)

---

## Phase 2: Localization Fixes

### 2.1 HIGH — Hardcoded English Error Messages in AccountStore

**File:** `Sources/Domain/Services/AccountStore.swift:60,65,102,201,211`
**Risk:** Non-English users see English errors

**Plan:**
1. Add 5 localization keys to `en.json`:
   - `account.error.handle_and_password_required`
   - `account.error.already_exists`
   - `account.error.failed_to_delete_credentials`
   - `account.error.failed_to_restore`
   - `account.error.failed_to_save`
2. Add translated equivalents to all 15 other language files
3. Replace hardcoded strings with `loc()` calls

**Effort:** 1h · **Dependencies:** None

### 2.2 HIGH — ModerationRulesView Displays Raw Enum Values

**File:** `Sources/Features/Lists/ModerationRulesView.swift:51,58`
**Risk:** Users see developer-internal enum raw values ("handleContains", "hasLabel")

**Plan:**
1. Add `localizedTitle: String` computed property on `ModerationRule.Trigger` — returns `loc("rules.trigger.\(rawValue)")`
2. Add `localizedTitle: String` computed property on `ModerationRule.Action` — returns `loc("rules.action.\(rawValue)")`
3. Add all trigger/action localization keys to `en.json` and all 15 other languages
4. Replace `Text(t.rawValue)` → `Text(t.localizedTitle)` and `Text(a.rawValue)` → `Text(a.localizedTitle)` in `ModerationRulesView.swift`

**Effort:** 0.5–1h · **Dependencies:** None

---

## Phase 3: Security Hardening

### 3.1 HIGH — Test Credentials in `.env` File

**Files:** `Tests/BlueskyModerationTests/LiveAuthenticationTests.swift:67-93`, `.env`
**Risk:** Credential leak via git commit or CI logs

**Plan:**
1. Verify `.env` is already in `.gitignore` — if not, add it
2. Migrate `LiveAuthenticationTests` to read from CI environment variables only (remove `.env` fallback)
3. Add a build configuration check that fails the test if no credential env vars are set (clear message)
4. Document in CONTRIBUTING.md how to set up credentials for live tests

**Effort:** 1h · **Dependencies:** None

---

## Phase 4: Major Refactors

### 4.1 HIGH — LiveBlueskyClient 927-Line Monolith

**File:** `Sources/Domain/Services/LiveBlueskyClient.swift` (927 lines)
**Risk:** Hard to test, maintain, or onboard to

**Plan:**
1. Identify responsibility boundaries — the class already conforms to multiple protocols:
   - `BlueskyAuthenticating` → `BlueskyAuthService`
   - `BlueskyListServicing` → `BlueskyListService` (note: collides with existing wrapper name)
   - `BlueskyProfileInspecting` → `BlueskyProfileService`
2. Extract each protocol conformance into its own `extension LiveBlueskyClient` in separate files:
   - `LiveBlueskyClient+Auth.swift`
   - `LiveBlueskyClient+List.swift`
   - `LiveBlueskyClient+Profile.swift`
3. Keep shared state (`session`, `requestExecutor`, `sessionService`) as `fileprivate` in the main file
4. Alternatively (preferred): Promote the existing `BlueskyProfileService`/`BlueskyListService` wrappers to be real implementations that own their logic, and have `LiveBlueskyClient` delegate to them

**Effort:** 4–6h · **Dependencies:** None (but >1.1, >1.2 should be done first for safety)

### 4.2 HIGH — PreviewBlueskyClient Duplicate Logic (428 lines)

**File:** `Sources/Domain/Services/PreviewBlueskyClient.swift` (428 lines)
**Risk:** Duplication between mock and real impl — changes to real service require parallel preview updates

**Plan:**
1. Create a `PreviewDataProvider` struct with static preview data factories
2. Replace override-heavy subclass with protocol-based mock objects
3. Use Swift's `#if DEBUG` conditional compilation for lightweight in-line preview data
4. Remove the `PreviewBlueskyClient` class entirely

**Effort:** 2–4h · **Dependencies:** 4.1 (since the interface being mocked may change)

---

## Phase 5: Test Coverage

### 5.1 HIGH — AccountStore Has Only 2 Tests

**File:** `Tests/BlueskyModerationTests/AccountStoreTests.swift` (2 tests)
**Risk:** No tests for `removeAccount`, `setActiveAccount`, `setLabel`, `moveAccount`, `refreshAccountProfiles`, `mergeCloudAccounts`

**Plan:**
Add tests for each untested method:
1. `removeAccount` — verify removal from array + keychain
2. `setActiveAccount` — verify activeAccountID updates
3. `setLabel` — verify label persists
4. `moveAccount` — verify reordering
5. `refreshAccountProfiles` — verify profile fetch and merge
6. `mergeCloudAccounts` — verify iCloud conflict resolution
7. Error states — empty handle, empty password, duplicate account
8. Persistence — verify `load()` restores state correctly

**Effort:** 3–4h · **Dependencies:** 3.1 (env fix for live tests), 2.1 (localization changes may affect error assertions)

### 5.2 HIGH — Zero UI Tests

**File:** `UITests/BlueskyModerationUITests/BlueskyModerationUITests.swift` (0 tests)
**Risk:** UI regressions undetectable in CI

**Plan:**
1. Add critical user flow tests:
   - Account add flow (tap add → fill handle → verify)
   - List navigation flow (tap list → verify members load)
   - Bulk operation flow (select members → perform action → verify)
   - Settings navigation
2. Use `XCUIApplication` with launch arguments to inject mock data
3. Configure CI to run UI tests on simulator

**Effort:** 6–8h · **Dependencies:** 4.1, 4.2 (stable service interfaces needed for mock injection)

---

## Summary Table

| # | Issue | Area | Effort | Dependencies |
|---|-------|------|--------|-------------|
| 1.1 | PinningDelegate accepts any cert | Security | 1–2h | None |
| 1.2 | SwiftLint disables critical rules | Tooling | 2–3h | None |
| 2.1 | AccountStore hardcoded English | i18n | 1h | None |
| 2.2 | ModerationRulesView raw enum values | i18n | 0.5–1h | None |
| 3.1 | Test credentials in `.env` | Security | 1h | None |
| 4.1 | LiveBlueskyClient 927-line monolith | Architecture | 4–6h | 1.1, 1.2 |
| 4.2 | PreviewBlueskyClient duplication | Architecture | 2–4h | 4.1 |
| 5.1 | AccountStore test gap (2 tests) | Testing | 3–4h | 3.1, 2.1 |
| 5.2 | Zero UI tests | Testing | 6–8h | 4.1, 4.2 |
| | **Total** | | **20.5–30h** | |

---

## Risk of Inaction

| Issue | If not fixed |
|-------|-------------|
| PinningDelegate | All API traffic vulnerable to MITM; JWT tokens can be intercepted |
| SwiftLint rules disabled | Force unwraps and TODOs silently accumulate; code quality declines |
| Hardcoded English | App appears unmaintained to non-English users |
| Raw enum values | Confusing/internally-inconsistent UX for moderation rule configuration |
| `.env` credentials | Credential leak via git or CI logs |
| Monolith client | Every new feature increases risk of regression; onboarding friction |
| Preview duplication | Maintenance burden grows with every interface change |
| AccountStore untested | Accidental data loss bugs ship to production |
| Zero UI tests | Each UI change risks regressions in critical flows |
