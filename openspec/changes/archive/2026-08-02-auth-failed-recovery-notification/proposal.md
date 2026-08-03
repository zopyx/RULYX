## Why

The re-login flow (`.authenticationFailed` → sheet + Re-Login buttons) never triggered in the most common expiry scenario: **when credential recovery itself fails**. `performAuthenticatedRequest` only posted the notification when the *operation* threw `.unauthorized` on the last attempt — but when the refresh token AND the stored app password are both stale (e.g. the user rotated the app password on bsky.social), `recoverSession` → `recreateSession` → `createSession` throws `.unauthorized` from inside the recovery path, which escaped uncaught. Result: error + RETRY, no Re-Login, forever.

## What Changes

- `BlueskySessionService.performAuthenticatedRequest` now catches `.unauthorized` from BOTH recovery entry points and posts `.authenticationFailed` before rethrowing:
  1. initial session restore (`cachedSession` → refresh/recreate failure)
  2. in-loop credential recovery (`recoverSession` → recreate failure)
- Regression test: `test401WithRecoveryFailureThrowsUnauthorized` asserts `.authenticationFailed` (with the account ID) is posted when recovery fails with rejected credentials.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `session-reauthentication`: The "Exhausted authentication retries SHALL trigger a re-login prompt" requirement now explicitly covers failures thrown by the credential-recovery path itself (not only the original operation).

## Impact

- `Sources/Domain/Services/BlueskySessionService.swift` — two new catch clauses
- `Tests/RULYXTests/BlueskySessionService401RetryTests.swift` — regression assertion
- No UI changes (existing sheet + Re-Login buttons now actually fire in the expiry scenario)
