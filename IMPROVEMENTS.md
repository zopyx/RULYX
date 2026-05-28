# RULYX 360-Degree Improvement Audit

Static audit date: 2026-05-27

This review covered the app surface, UX, tests, architecture, and security. No source files were changed during the audit.

## Ratings

| Section | Code quality rating | Assessment |
|---|---:|---|
| App | 7/10 | Feature-rich and broad, but high surface complexity |
| UX | 6.5/10 | Strong iPhone/iPad intent, but workflows are dense and some polish gaps remain |
| Tests | 6/10 | Many unit tests, but weak UI assertions and skipped guarantees |
| Architecture | 6.5/10 | Clear layers exist, but several god objects and lifecycle coupling |
| Security | 5.5/10 | Good Keychain baseline, but sensitive export/debug/lock issues need attention |

## App Improvements

1. Reduce very large files: `Sources/Domain/Services/LiveBlueskyClient.swift`, `Sources/Features/Lists/BlueskyProfileView.swift`, and `Sources/Domain/Services/BlueskyAPIDTOs.swift`.
2. Split beta features into explicit feature modules with separate dependency gates.
3. Add an app-level health/status model instead of scattering Clearsky, chat, and push lifecycle across `Sources/App/RULYXApp.swift`.
4. Add first-class empty, error, and retry states for each network-heavy tab.
5. Normalize account context APIs so the active/search account split is harder to misuse.
6. Move screenshot/live test credential behavior behind a dedicated test harness.
7. Make cache policy explicit per service instead of relying on a broad shared URL cache.
8. Add user-facing offline/degraded-state affordances for Bluesky API failures, not only Clearsky.
9. Reconcile `WidgetExtension` presence with `project.yml`; it exists but is not modeled in the project.
10. Exclude `build`, `.derived*`, and `WidgetExtension` from formatter/lint or add them intentionally.

## UX Improvements

1. Add a real app-lock overlay: `LockScreenView` exists, but `AppLockManager.isLocked` is not rendered in `RULYXApp`.
2. Replace hidden HTTP debug double-tap access with an explicit gated path in `SettingsView`.
3. Simplify high-density profile/list screens with progressive disclosure and pinned primary actions.
4. Audit icon-only buttons for 44pt hit targets and localized accessibility labels.
5. Use consistent localized `Text(loc:)` keys; several buttons use raw keys like `Button("actions.ok")`.
6. Add destructive-action previews for bulk moderation, deletes, imports, and block-back.
7. Improve onboarding for first account setup; account creation is the real first task.
8. Add visible feedback when account switching clears caches and reloads data.
9. Test Dynamic Type, RTL Arabic, and iPad split widths visually.
10. Reduce reliance on sheets stacked from large views; several flows can become dedicated navigation destinations.

## Test Improvements

1. Fix lint first; `make lint` currently fails before `swiftlint`.
2. Remove unconditional skips in `Tests/RULYXTests/LocalizationCompletenessTests.swift`.
3. Add UI assertions for actual screen content, not only "tab bar still visible" in `UITests/RULYXUITests/RULYXUITests.swift`.
4. Add tests for app-lock overlay integration, not only `AppLockManager`.
5. Add tests for account export/import security behavior.
6. Add HTTP debug redaction tests for URLs, JSON bodies, headers, and Klipy paths.
7. Add contract tests for active account vs preferred search account routing.
8. Add snapshot or visual tests for iPad `NavigationSplitView`.
9. Add tests for custom PDS URL validation and rejection of non-HTTPS endpoints.
10. Make live tests opt-in and separate from deterministic CI.

## Architecture Improvements

1. Break `Sources/Domain/Services/LiveBlueskyClient.swift` into actor, profile, list, feed, and chat facade services.
2. Move launch lifecycle orchestration out of `Sources/App/RULYXApp.swift` into an `AppLifecycleCoordinator`.
3. Avoid `@unchecked Sendable` where possible; wrap mutable state in actors or locks.
4. Replace `NotificationCenter` navigation/account events with typed coordinators.
5. Make dependency protocols public/internal consistently and inject service protocols, not concrete `LiveBlueskyClient`.
6. Move DTOs into endpoint-specific files.
7. Extract import/export account logic from `Sources/Features/Accounts/AccountTabView.swift`.
8. Standardize async task cancellation for search, timeline, and list loading.
9. Introduce domain-specific use cases for bulk moderation operations.
10. Add architecture tests that prevent views from directly reaching low-level services where inappropriate.

## Security Improvements

1. Stop exporting app passwords as plaintext JSON to temp files in `AccountTabView`.
2. Actually render `LockScreenView` when `AppLockManager.isLocked` is true.
3. Remove hidden HTTP debug access when debug mode is off in `SettingsView`.
4. Use the pinned session or remove dead pinning code; `BlueskyRequestExecutor.makePinnedSession()` is not wired into default networking.
5. Do not seed a Klipy API key in code in `GIFService`.
6. Validate custom PDS URLs as HTTPS before account auth in `AddAccountView`.
7. Redact authorization headers and broader secret-like fields in debug logs, not only selected URL/query patterns.
8. Fix sanitizer range reuse after string replacement in `HTTPRequestDebugStore`.
9. Add biometric/passcode confirmation before destructive moderation actions, not only account import/export.
10. Update `PrivacyInfo.xcprivacy` to reflect network/user/account data handling more explicitly.

## Verification

`make lint` was run and failed at `swiftformat --lint` before `swiftlint`. The failures were mostly formatting issues in tests/UI tests plus formatter traversal into generated/build-related files such as `build/.../GeneratedAssetSymbols.swift`.

| Area | Change | Impact |
|---|---|---|
| Files modified | `IMPROVEMENTS.md` | Added the requested audit summary and improvement backlog |
