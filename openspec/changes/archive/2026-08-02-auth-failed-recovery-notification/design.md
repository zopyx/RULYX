# Design — auth-failed-recovery-notification

## Context

`performAuthenticatedRequest` posted `.authenticationFailed` only when the user-facing operation threw `.unauthorized` on its final attempt. The expiry scenario that actually happens in the wild — app password rotated on bsky.social, refresh token revoked — fails EARLIER: `recoverSession` (refresh → recreate-from-keychain) throws `.unauthorized` from inside the `catch` block of the retry loop, escaping without the notification. Same for the initial `cachedSession` restore.

## Decisions

### D1 — Catch auth errors at both recovery entry points
- Wrap the initial `cachedSession` call: `catch let BlueskyAPIError.unauthorized(message)` → `postAuthenticationFailed(for:message:)` → rethrow.
- Inside the loop's recovery: add `catch let BlueskyAPIError.unauthorized(recoveryMessage)` alongside the existing `missingCredentials` catch → post → rethrow.
- Behavior otherwise unchanged: recovery failures still abort immediately (no pointless retries with known-stale credentials); the original error type/message propagates.

### D2 — Regression test
`test401WithRecoveryFailureThrowsUnauthorized` (which seeds the keychain password) now asserts via `expectation(forNotification: .authenticationFailed)` that the notification fires with the account ID. This test failed to compile/fulfill before the fix.

## Files

| File | Change |
|------|--------|
| `Sources/Domain/Services/BlueskySessionService.swift` | 2 new catch clauses (initial restore + in-loop recovery) |
| `Tests/RULYXTests/BlueskySessionService401RetryTests.swift` | notification assertion |

## Risks
- The notification now fires once per failing request (chat polling etc.). The sheet re-presents after dismissal — intended (the session is broken until re-login). `ReauthenticationPromptState` keeps Re-Login buttons visible until success/switch.
