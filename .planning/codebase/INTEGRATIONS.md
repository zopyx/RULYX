# External Integrations

**Analysis Date:** 2026-05-12

## AT Protocol / Bluesky API

**Base URL:** `https://bsky.social` (`Sources/Shared/Support/URL+Bluesky.swift`, line 4)
**API Path Prefix:** All requests go to `{hostURL}/xrpc/{path}` (`Sources/Domain/Services/BlueskyRequestExecutor.swift`, line 46)
**Public API URL:** `https://public.api.bsky.app` (used for profile batch lookups — `LiveBlueskyClient.swift`, line 638)

### Authentication Endpoints

| Endpoint | Method | Purpose | File | Lines |
|----------|--------|---------|------|-------|
| `com.atproto.server.createSession` | POST | Login with handle + app password | `BlueskySessionService.swift` | 43–49 |
| `com.atproto.server.refreshSession` | POST | Refresh expired JWT | `BlueskySessionService.swift` | 177–183 |
| `com.atproto.identity.resolveHandle` | GET | Resolve handle → DID | `BlueskySessionService.swift` | 256–263 |
| `com.atproto.identity.resolveDid` | GET | Resolve DID → DID Document (for PDS URL) | `BlueskySessionService.swift` | 267–274 |

### Moderation & List Endpoints

| Endpoint | Method | Purpose | File | Lines |
|----------|--------|---------|------|-------|
| `app.bsky.graph.getLists` | GET | Fetch user's moderation/curation lists | `LiveBlueskyClient.swift` | 84–93 |
| `app.bsky.graph.getList` | GET | Fetch paginated list members | `LiveBlueskyClient.swift` | 157–163 |
| `app.bsky.graph.getListsWithMembership` | GET | Check profile's list memberships | `LiveBlueskyClient.swift` | 861–869 |
| `app.bsky.graph.getStarterPacksWithMembership` | GET | Check profile's starter pack memberships | `LiveBlueskyClient.swift` | 871–879 |
| `app.bsky.actor.searchActorsTypeahead` | GET | Search actors by name/handle | `LiveBlueskyClient.swift` | 221–228 |
| `app.bsky.actor.getProfile` | GET | Fetch full profile details | `LiveBlueskyClient.swift` | 506–515 |
| `app.bsky.actor.getProfiles` | GET | Batch profile lookup (public API) | `LiveBlueskyClient.swift` | 636–652 |
| `app.bsky.graph.getFollowers` | GET | Fetch paginated followers | `LiveBlueskyClient.swift` | 752–758 |
| `app.bsky.graph.getFollows` | GET | Fetch paginated following | `LiveBlueskyClient.swift` | 821–827 |
| `com.atproto.repo.createRecord` | POST | Add list member / create list / block actor | `LiveBlueskyClient.swift` | 263–273 |
| `com.atproto.repo.deleteRecord` | POST | Remove list member / delete list / unblock | `LiveBlueskyClient.swift` | 293–301 |
| `com.atproto.repo.putRecord` | POST | Update list metadata | `LiveBlueskyClient.swift` | 396–403 |
| `app.bsky.graph.muteActor` | POST | Mute an actor | `LiveBlueskyClient.swift` | 465–473 |
| `app.bsky.graph.unmuteActor` | POST | Unmute an actor | `LiveBlueskyClient.swift` | 485–493 |

### Client Implementation

- **Network Layer:** `BlueskyRequestExecutor` (`Sources/Domain/Services/BlueskyRequestExecutor.swift`) — struct conforming to `BlueskyRequestExecuting` protocol
- **Session Layer:** `BlueskySessionService` (`Sources/Domain/Services/BlueskySessionService.swift`) — manages JWT lifecycle, auto-refresh on 401
- **Request pattern:** All authenticated requests go through `performAuthenticatedRequest` which retries with refreshed JWT on `401`
- **User-Agent:** `"Rulyx Moderation App"` on all requests (`BlueskyRequestExecutor.swift`, line 59)

## Authentication

**Mechanism:** Bluesky App Passwords
- Users enter handle + app password
- `com.atproto.server.createSession` returns `accessJWT` + `refreshJWT` tokens
- JWT token expiry checked via base64 payload decoding (`BlueskySessionService.swift`, lines 306–323)
- Tokens auto-refreshed when expiry is within 60 seconds (`BlueskySessionService.swift`, lines 298–304)

### Credential Storage

- **App Passwords:** Stored in iOS Keychain (`AccountStore.swift`, line 85)
  - Service: `com.ajung.BlueskyModeration.password`
  - Account: account `UUID.uuidString`
  - Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Session JWTs:** Stored in iOS Keychain (`BlueskySessionService.swift`, line 72)
  - Service: `com.ajung.BlueskyModeration.session`
  - Account: account `UUID.uuidString`
  - Encoded as JSON string via `JSONEncoder`
- **Keychain Service:** `KeychainService` (`Sources/Domain/Services/KeychainService.swift`, line 15) — wraps `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` for `kSecClassGenericPassword`

### Session Management

- In-memory cache: `cachedSessions: [String: BlueskySession]` dictionary (`BlueskySessionService.swift`, line 22)
- On `401`, attempts `com.atproto.server.refreshSession` with `refreshJWT`
- If refresh fails, re-authenticates with saved app password (if available)
- If no app password stored, throws `BlueskyAPIError.missingCredentials`

## Third-Party Services

### Clearsky

**Base URL:** `https://public.api.clearsky.services/api/v1/anon/`

| Endpoint | Purpose | File | Lines |
|----------|---------|------|-------|
| `/{endpoint}/{did}` | Fetch blocklist (blocked or blocked-by) | `LiveBlueskyClient.swift` | 575–577 |
| `/{endpoint}/total/{did}` | Fetch blocklist count | `LiveBlueskyClient.swift` | 601 |
| `/get-did/{handle}` | Resolve handle → DID | `LiveBlueskyClient.swift` | 664–665 |

- **Used for:** Block list fetching (since AT Protocol doesn't expose this directly)
- **Auth:** None (public anonymous API)
- **User-Agent:** `"Rulyx Moderation App"`

### PLC Directory

**Base URL:** `https://plc.directory`

| Endpoint | Purpose | File | Lines |
|----------|---------|------|-------|
| `/{did}/log/audit` | Fetch DID audit log for handle history | `LiveBlueskyClient.swift` | 691–701 |

- **Used for:** Profile inspection — display handle change history
- **Auth:** None (public API)

## Data Storage

### UserDefaults

Used for local persistence of all app state. **Privacy manifest** (`PrivacyInfo.xcprivacy`, line 15) declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.

| Key | Data | File | Lines |
|-----|------|------|-------|
| `bluesky.savedAccounts` | Encoded `[AppAccount]` | `AccountStore.swift` | 186–191 |
| `bluesky.activeAccountID` | Active account UUID string | `AccountStore.swift` | 192–199 |
| `moderation.savedProfileSearches` | Encoded `[SavedProfileSearch]` | `WorkspacePreferencesStore.swift` | 114–118 |
| `moderation.recentProfileSearches` | `[RecentProfileSearch]` | `WorkspacePreferencesStore.swift` | 120–124 |
| `moderation.lastProfileQuery` | String | `WorkspacePreferencesStore.swift` | 126 |
| `moderation.listSnapshots` | `[String: [ListMembershipSnapshot]]` | `ModerationAuditStore.swift` | 220–224 |
| `moderation.operationLog` | `[ModerationOperationLogEntry]` | `ModerationAuditStore.swift` | 226–230 |
| `selectedLanguage` | String (e.g. "en", "de") | `LocalizationManager.swift` | 37 |
| `widgetListCounts` | `[WidgetListCount]` (shared) | `WidgetExtension/RulyxWidget.swift` | 27–28 |
| `appLockEnabled` | Bool (@AppStorage) | `AppLockManager.swift` | 11 |
| `appLockTimeout` | Int (minutes) (@AppStorage) | `AppLockManager.swift` | 19 |
| `iCloudSyncEnabled` | Bool | `iCloudAccountSync.swift` | 10 |

### File System Cache

| Cache | Location | File | Lines |
|-------|----------|------|-------|
| Dashboard data | `Library/Caches/com.ajung.BlueskyModeration/dashboard_{key}.json` | `DashboardCache.swift` | 11–18 |
| Relationship data | `Library/Caches/com.ajung.BlueskyModeration/{key}.json` | `RelationshipCache.swift` | 4–11 |

### iCloud Sync

**Mechanism:** `NSUbiquitousKeyValueStore` (simple key-value, NOT CloudKit)
- **File:** `Sources/Shared/Support/iCloudAccountSync.swift`
- **Data synced:** Account metadata (handle, did, pdsURL, label) — **NOT** app passwords or session tokens
- **Sync trigger:** `pushAccounts()` called after every account mutation in `AccountStore.persist()` (line 213)
- **Enabled by default:** `isEnabled = true` unless user toggles off in Settings
- **Observers:** Listens to `NSUbiquitousKeyValueStore.didChangeExternallyNotification` (line 20)

### No database
- **No Core Data, SQLite, or SwiftData** — all persistence is UserDefaults + Keychain + file system cache

## Caching & Performance

- **URL cache:** `URLCache.shared` cleared on `clearCache()` call (`LiveBlueskyClient.swift`, lines 53–57)
- **Session cache:** In-memory `cachedSessions` dictionary cleared on `clearSessionCache()` and app logout
- **File cache:** `DashboardCache` and `RelationshipCache` use JSON files in `Library/Caches/`
- **Pinned URLSession:** Ephemeral session via `PinningDelegate` for `bsky.social` requests (`BlueskyRequestExecutor.swift`, lines 115–131) — trusts server certificate directly (does NOT perform full certificate pinning against a known hash)

## Analytics & Telemetry

- **No third-party analytics** (no Firebase, Mixpanel, Amplitude, etc.)
- **No crash reporting** (no Crashlytics, Sentry, etc.)
- **No performance monitoring** (no New Relic, Datadog, etc.)

### Logging (os.log / Unified Logging)

**File:** `Sources/Shared/Support/AppLogger.swift`

| Logger | Category | Usage |
|--------|----------|-------|
| `AppLogger.search` | `search` | Actor search queries and results |
| `AppLogger.persistence` | `persistence` | Snapshot saves, operation recording |
| `AppLogger.moderation` | `moderation` | Bulk operations, account refreshes |
| `AppLogger.performance` | `performance` | Request timing, decoding failures |

All loggers use `privacy: .public` on non-sensitive parameters for debug accessibility.

## CI/CD & Deployment

- **No CI pipeline detected** — no `.github/` directory, no `Makefile`, no shell scripts
- **No deployment automation** — no Fastlane, no build scripts
- **Hosting:** N/A (native iOS app, distributed via TestFlight / App Store)
- **Versioning:** Manual — `MARKETING_VERSION: "1.0.0"`, `CURRENT_PROJECT_VERSION: "1"` in `project.yml` (lines 31–32)

## Widget Extension

- **Target:** WidgetExtension (separate widget bundle)
- **Data sharing:** `UserDefaults.standard` (shared with main app via app group — **not configured**, uses standard defaults)
- **No networking in widget** — reads pre-cached data only

## Privacy & Security

- **Face ID usage:** Declared in `project.yml` (line 29): `NSFaceIDUsageDescription`
- **Privacy manifest:** `PrivacyInfo.xcprivacy` declares UserDefaults access (reason `CA92.1`)
- **No tracking:** `NSPrivacyTracking = false` (PrivacyInfo.xcprivacy, line 6)
- **No collected data types:** Empty `NSPrivacyCollectedDataTypes` array (line 10)

## Environment Configuration

**Required env vars (from `.env` file — DO NOT read contents):**
- Not enumerated (`.env` file present but contents protected)

**Secrets location:**
- iOS Keychain (app passwords, session JWTs) — `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

## Webhooks & Callbacks

**Incoming:** None
**Outgoing:** None

---

*Integration audit: 2026-05-12*
