# RULYX — Roadmap to 9.5/10

> Current: Architecture 8.5 · Testing 8.0 · QA/CI 5.5 · Type Safety 9.0 · Security 9.0 · i18n 8.5 · Build 7.5

---

## Architecture: 8.5 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| A1 | BlueskyProfileView → ViewModel extraction (1945 LOC, ~30 service calls, last god view) | 4-6h | 🔴 High |
| A2 | Eliminate `container.blueskyClient` passthrough — views use individual protocols (`container.profile`, `container.list`, etc.) | 8-10h | 🟡 Medium |
| A3 | Remove `.environmentObject(deps.blueskyClient)` from standalone `WindowGroup` | 1h | 🟢 Low |

**Approach for A1:** Follow the `ComposePostViewModel` pattern — `@MainActor ObservableObject`, protocol-typed DI, move all async functions out of the view body. Extract in stages: block-back logic (already partially done via `BlueskyProfileActionsViewModel`), profile data loading, list membership, moderation actions, export.

**Approach for A2:** Replace `container.blueskyClient.fetchProfile(...)` with `container.profile.fetchProfile(...)` etc. Each view declares only the protocols it actually uses. Allows per-protocol mocking in tests.

---

## Testing: 8.0 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| T1 | Coverage ≥ 80% enforced in CI (`xcodebuild -enableCodeCoverage YES`) | 2h | 🔴 High |
| T2 | ComposePostVM: error-path tests (upload failure, post failure, edit delete failure) + image upload progress tests | 3h | 🟡 Medium |
| T3 | BlueskyProfileActionsVM: full state matrix (every `@Published` transition, every error path) | 3h | 🟡 Medium |
| T4 | Service integration tests: `LiveBlueskyClient` with `MockURLProtocol` for key API flows | 4h | 🟡 Medium |
| T5 | Fix UI tests: 16/17 failing → all green (tab bar accessibility identifiers added, need query updates) | 3h | 🟡 Medium |
| T6 | Snapshot tests: iPad variants, dark mode, Dynamic Type `.accessibility5`, RTL Arabic | 4h | 🟢 Low |
| T7 | Performance regression tests: baseline `XCTMetric` for timeline load, profile fetch, list members | 3h | 🟢 Low |

---

## QA / CI: 5.5 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| Q1 | Code coverage badge in README + minimum 80% threshold in CI (`xcrun xccov view --report --json`) | 2h | 🔴 High |
| Q2 | Pre-push Git hook: architecture violation check (view→service import), localization key sync, lint | 2h | 🔴 High |
| Q3 | Automated accessibility audit: run XCUI accessibility inspector in CI, fail on violations | 3h | 🟡 Medium |
| Q4 | Fastlane screenshot automation: `fastlane screenshots` with live credentials, upload to App Store Connect | 3h | 🟡 Medium |
| Q5 | Nightly build + test via GitHub Actions scheduled cron (`0 2 * * *`) | 1h | 🟢 Low |
| Q6 | Automatic TestFlight upload on version tag push (`on: push: tags: 'v*'`) | 2h | 🟢 Low |

---

## Type Safety: 9.0 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| S1 | Migrate `ObservableObject` → `@Observable` (Swift 5.9+ macro, removes `@unchecked Sendable` need) | 4h | 🟡 Medium |
| S2 | Audit remaining model types for missing `Sendable` conformance | 2h | 🟢 Low |
| S3 | Remove last `@unchecked Sendable` from `ActionBox` (refactor to use `@Sendable` closure directly) | 1h | 🟢 Low |

---

## Security: 9.0 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| P1 | Add actual certificate hashes to `CertificatePinningDelegate.pinnedHashes` (extract from `bsky.social`, `api.clearsky.app`) | 2h | 🔴 High |
| P2 | App Transport Security audit: verify all domains use HTTPS, no `NSAllowsArbitraryLoads` | 1h | 🟡 Medium |
| P3 | Mark password/token fields with `isSecureTextEntry = true` | 1h | 🟢 Low |

---

## i18n: 8.5 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| I1 | Machine-translate remaining English stubs in non-English files (ar, ja, zh, ko, ru, th, vi have ~200 English fallbacks each) | 4h | 🟡 Medium |
| I2 | RTL layout audit: run app in Arabic, fix flipped layouts, test with snapshot tests | 3h | 🟡 Medium |
| I3 | Pluralization audit: verify `{n}` placeholders work correctly across all 16 languages | 2h | 🟢 Low |

---

## Build: 7.5 → 9.5

| # | Task | Effort | Impact |
|---|------|--------|--------|
| B1 | CI caching: DerivedData + SPM packages via `actions/cache@v4` | 1h | 🔴 High |
| B2 | Parallel test execution: split `RULYXTests` across multiple simulator instances | 2h | 🟡 Medium |
| B3 | Localization validation in CI: run `validate-translations.py` as CI step, fail on missing keys | 1h | 🟡 Medium |
| B4 | Build time regression detection: record baseline, alert on >20% increase | 2h | 🟢 Low |

---

## Execution Order (by impact)

```
Week 1:  T1 T5 Q1 Q2 B1           ← Testing + CI foundations
Week 2:  A1 T2 T3 T4               ← Architecture + VM tests
Week 3:  A2 A3 I1 I2 P1 P2        ← Protocol wiring + i18n + certs
Week 4:  Q3 Q4 Q5 Q6 B2 B3 B4 S1 S2 S3 I3 P3  ← Polish
```

**Total: ~80 hours** (4 weeks solo, 2 weeks with pair).

---

## Score Projections

| Milestone | Arch | Test | QA | Type | Sec | i18n | Build |
|-----------|------|------|----|------|-----|------|-------|
| Now       | 8.5  | 8.0  | 5.5| 9.0  | 9.0 | 8.5  | 7.5   |
| Week 1    | 8.5  | 8.5  | 7.0| 9.0  | 9.0 | 8.5  | 8.0   |
| Week 2    | 9.0  | 9.0  | 7.0| 9.0  | 9.0 | 8.5  | 8.0   |
| Week 3    | 9.5  | 9.0  | 7.5| 9.0  | 9.5 | 9.0  | 8.5   |
| Week 4    | 9.5  | 9.5  | 9.5| 9.5  | 9.5 | 9.5  | 9.5   |
