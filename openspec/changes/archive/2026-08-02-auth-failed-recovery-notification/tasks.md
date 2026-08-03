# Tasks — auth-failed-recovery-notification

- [x] Catch `.unauthorized` from initial `cachedSession` restore → post `.authenticationFailed` → rethrow
- [x] Catch `.unauthorized` from in-loop `recoverSession` → post `.authenticationFailed` → rethrow
- [x] Regression test: `test401WithRecoveryFailureThrowsUnauthorized` asserts notification + accountID
- [x] Verify: unit tests (AppErrorTests, 401Retry, ServiceIntegration — 27/27 green), swiftformat, swiftlint, build
- [x] `openspec validate` + archive
