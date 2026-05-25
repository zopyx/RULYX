# Block Back — Technical & UX Specification

> **Status:** Implemented (Beta, behind `showBetaFeatures` flag)
> **Author:** RULYX
> **Last updated:** 2026-05-22

---

## Table of Contents

1. [Overview](#1-overview)
2. [User Story](#2-user-story)
3. [UX Flow](#3-ux-flow)
4. [Screen-by-Screen Specification](#4-screen-by-screen-specification)
5. [Data Model](#5-data-model)
6. [API Contracts](#6-api-contracts)
7. [Service Layer Architecture](#7-service-layer-architecture)
8. [State Machine](#8-state-machine)
9. [Error Handling](#9-error-handling)
10. [Concurrency Model](#10-concurrency-model)
11. [Localization Keys](#11-localization-keys)
12. [Testing Guide](#12-testing-guide)
13. [Security & Privacy Considerations](#13-security--privacy-considerations)
14. [Performance Considerations](#14-performance-considerations)
15. [Dependencies](#15-dependencies)

---

## 1. Overview

The **Block Back** feature allows a Bluesky user to mass-block all accounts that block them but that they have not yet blocked back. It operates exclusively through the **ClearSky API** (a public, third-party index of Bluesky block records). It is gated behind both an **own-profile check** and the **`showBetaFeatures`** user-defaults flag.

The feature has five distinct phases:

| Phase | What happens | UI state |
|-------|-------------|----------|
| **Idle** | Block counts are fetched from ClearSky on profile load | Three `LabeledContent` rows showing Blocking / Blocked by / Accounts not yet blocked |
| **Preview** | User taps the "Accounts not yet blocked" row; a sheet opens listing each unblocked blocker with avatar, handle, and status indicators | Sheet with scrollable list + "Block Back" action button |
| **Confirm** | User taps "Block Back"; two consecutive confirmation dialogs are shown | Native iOS alert sheets (`.alert` modifier) |
| **Execution** | The app batches and blocks all identified accounts concurrently via the Bluesky AT Protocol | Deterministic progress bar + "X/Y blocked" overlay |
| **Result** | A summary banner is shown for 4 seconds, then auto-dismisses | Green checkmark (all succeeded) or orange warning (partial failures) |

---

## 2. User Story

> "As a Bluesky user, I want to see a list of accounts that block me but that I haven't blocked back, review them in a preview sheet, and then mass-block them with a single action, seeing real-time progress and a final result summary."

### Acceptance Criteria

1. **AC-1:** Block counts are loaded automatically when viewing own profile (gated by `showBetaFeatures`).
2. **AC-2:** Three counts are displayed: "Blocking" (accounts I block), "Blocked by" (accounts that block me), "Accounts not yet blocked" (the DID-level set difference).
3. **AC-3:** Tapping "Accounts not yet blocked" opens a preview sheet listing each candidate account with avatar, display name, handle, "Blocks me" badge, and "Not blocked back" badge.
4. **AC-4:** The preview sheet has a "Block Back" button that is disabled when the list is empty.
5. **AC-5:** Tapping "Block Back" triggers a two-step confirmation with escalating severity (first: "Block N accounts?", second: "Are you sure? This cannot be undone.").
6. **AC-6:** After final confirmation, a linear progress bar appears showing `completed / total` with a live counter.
7. **AC-7:** Blocks are executed in concurrent batches of 5, with 300ms delay between batches to avoid rate limits.
8. **AC-8:** After completion, a result banner shows for 4 seconds: green if all succeeded, orange if any failed, with a summary string.
9. **AC-9:** After the result dismisses, block counts are re-fetched to reflect the new state.
10. **AC-10:** All Clearsky API calls are gated by `ClearskyHeartbeatService.isClearskyAvailable`. If Clearsky is down, a red banner appears and block-back is not possible.

---

## 3. UX Flow

```mermaid
flowchart TD
    A[Own Profile Loads] --> B[fetchBlockCounts]
    B --> C{Clearsky available?}
    C -->|No| D[Show red ClearskyBanner<br>Block counts stay nil]
    C -->|Yes| E[Display counts<br>Blocking | Blocked by |<br>Accounts not yet blocked]
    E --> F{unblockedBlockersCount > 0?}
    F -->|No| G[Show "All clear"<br>green checkmark label]
    F -->|Yes| H[Show cheveron on<br>"Accounts not yet blocked"]
    H --> I[User taps row]
    I --> J[fetchBlockPreview]
    J --> K[Open preview sheet<br>with actor list]
    K --> L[User taps "Block Back"]
    L --> M[Alert 1: "Block N accounts?"]
    M -->|Cancel| N[Return to sheet]
    M -->|Block Back| O[Alert 2: "Are you sure?<br>This cannot be undone."]
    O -->|Cancel| P[Return to profile]
    O -->|Destructive confirm| Q[blockBack execution]
    Q --> R[Show progress bar]
    R --> S[Show result summary<br>(4s auto-dismiss)]
    S --> T[fetchBlockCounts<br>(refresh counts)]
```

---

## 4. Screen-by-Screen Specification

### 4.1 Profile Section — "Block Back" Header

**Location:** `BlueskyProfileView.swift`, inside `Section { }` with header `Text(loc: "profile.block_back.section")`.

**Visibility:** Only when `isOwnProfile == true && showBetaFeatures == true`.

The header includes an **orange "BETA" badge**:
```swift
HStack(spacing: 6) {
    Text(loc: "profile.block_back.section")    // "Block Back"
    Text(loc: "profile.beta")                    // "BETA"
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
}
```

**Loading state:** When `isFetchingBlockCounts == true`, a single row with `ProgressView` + "Loading block info…" text is shown instead of all other content.

### 4.2 Count Rows

Three `LabeledContent` rows, always shown together when not loading:

| Row | Key | Value source | Example |
|-----|-----|-------------|---------|
| "Blocking" | `profile.block_back.blocking` | `blockingCount: Int?` | `12` |
| "Blocked by" | `profile.block_back.blocked_by` | `blockedByCount: Int?` | `8` |
| "Accounts not yet blocked" | `profile.block_back.unblocked` | `unblockedBlockersCount: Int?` | `5` |

The "Accounts not yet blocked" row is wrapped in a `Button` with `.buttonStyle(.plain)`. When `unblockedBlockersCount > 0`, a **chevron** (`chevron.right`) is shown on the trailing edge. Tapping triggers `fetchBlockPreview()`.

### 4.3 Action / Progress / Result States

After the three count rows, one of four mutually exclusive states is rendered:

#### State A: Progress Bar (`isBlockingBack && blockBackTotal > 0`)
```swift
ProgressView(value: Double(blockBackCompleted), total: Double(blockBackTotal))
    .progressViewStyle(.linear)
    .tint(Color.skyPrimary)
```
Below: `Text("Blocking back 3/5…")` with `{completed}` and `{total}` substitutions.

#### State B: Result Summary (`showBlockBackResult`)
- **All succeeded** (failureCount == 0): green `checkmark.circle.fill` + summary text from `blockBackResultSummary`
- **Partial failures** (failureCount > 0): orange `exclamationmark.triangle.fill` + summary text
- Auto-dismisses after 4 seconds.

#### State C: "All clear" (`blockedByCount > 0` and no unblocked blockers)
- `Label("profile.block_back.all_clear", systemImage: "checkmark.circle.fill")` in green.
- Only shown when `blockedByCount > 0`.

#### State D: "No one blocking" (`blockedByCount == 0`)
- `Label("profile.block_back.none_blocking", systemImage: "checkmark.circle.fill")` in green.

### 4.4 Error Row

If `blockBackError` is non-nil, a red caption is shown below the states. This only appears when `blockBack` threw an error **before** any blocks completed (i.e., both successCount and failureCount are 0).

### 4.5 Preview Sheet

Triggered by setting `showBlockBackPreview = true`. Immediately after, `fetchBlockPreview()` runs.

**Loading state:** A `List` with a centered `ProgressView` and no section header. Toolbar has only a close button.

**Empty state:** A `List` with `Text(loc("profile.block_back.preview.empty"))`. Toolbar has only a close button.

**Populated state:** A `List` with an `.insetGrouped` style containing a single `Section`. The section header shows `"{count} account(s) that block you but are not blocked back"`. Each row is:

```
[avatar 36x36 circle]  Display Name          [hand.raised.slash.fill  "Blocks me"]     (red)
                        @handle              [hand.raised.slash       "Not blocked back"] (secondary)
```

- Avatar uses `AsyncImage` with a circular placeholder (first letter of display name).
- Toolbar has a close button (top-leading) and a **"Block Back" button** (top-trailing, `.confirmationAction` placement).
- "Block Back" button is disabled when `blockPreviewActors.isEmpty`.
- Tapping "Block Back" dismisses the sheet and sets `showBlockBackConfirm1 = true`.

### 4.6 Confirmation Dialogs

Two consecutive `.alert` sheets:

#### Alert 1: "Block Back"
- Title: `loc("profile.block_back.confirm.first.title")`
- Message: `"Block {count} account(s) that block you but aren't blocked back?"`
- Buttons: Cancel (role: `.cancel`) | **Block Back** (no role, triggers Alert 2)
- Triggered by: `showBlockBackConfirm1`

#### Alert 2: "Are you sure?"
- Title: `loc("profile.block_back.confirm.second.title")`
- Message: `"This cannot be undone."`
- Buttons: Cancel (role: `.cancel`) | **Block Back** (role: `.destructive`, triggers `blockBack()`)
- Triggered by: `showBlockBackConfirm2`

---

## 5. Data Model

### 5.1 `BlueskyActor`

```swift
struct BlueskyActor: Identifiable, Hashable, Codable {
    let id: String           // defaults to did
    let did: String
    let handle: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date?
    var blockedDate: Date?   // populated by Clearsky (from blocklist entry)
    var description: String?
}
```

### 5.2 `ClearskyBlocklistResult`

```swift
struct ClearskyBlocklistResult {
    let actors: [BlueskyActor]
    let totalCount: Int      // always == actors.count in current impl
}
```

### 5.3 Clearsky API DTOs

```swift
struct ClearskyBlocklistResponse: Decodable {
    let data: ClearskyBlocklistData
}
struct ClearskyBlocklistData: Decodable {
    let blocklist: [ClearskyBlocklistEntry]
}
struct ClearskyBlocklistEntry: Decodable {
    let did: String
    let blockedDate: String   // ISO 8601 date string, coded as "blocked_date"
}
```

### 5.4 View State Properties

All stored as `@State` in `BlueskyProfileView`:

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `blockingCount` | `Int?` | `nil` | Number of accounts I block (from ClearSky "blocklist") |
| `blockedByCount` | `Int?` | `nil` | Number of accounts that block me (from ClearSky "single-blocklist") |
| `unblockedBlockersCount` | `Int?` | `nil` | Set difference: `blockedByDIDs - blockingDIDs` |
| `isFetchingBlockCounts` | `Bool` | `false` | Loading indicator for initial count fetch |
| `isBlockingBack` | `Bool` | `false` | Whether block-back execution is in progress |
| `blockBackCompleted` | `Int` | `0` | How many blocks have been attempted so far |
| `blockBackTotal` | `Int` | `0` | Total blocks to perform in current batch |
| `blockBackSuccessCount` | `Int` | `0` | Count of succeeded blocks |
| `blockBackFailureCount` | `Int` | `0` | Count of failed blocks |
| `blockBackError` | `String?` | `nil` | Error message if `blockBack()` threw before any blocks |
| `showBlockBackResult` | `Bool` | `false` | Whether to show result summary (auto-dismisses after 4s) |
| `showBlockBackConfirm1` | `Bool` | `false` | Triggers first confirmation alert |
| `showBlockBackConfirm2` | `Bool` | `false` | Triggers second (destructive) confirmation alert |
| `showBlockBackPreview` | `Bool` | `false` | Triggers preview sheet |
| `blockPreviewActors` | `[BlueskyActor]` | `[]` | Actors shown in preview sheet |
| `isFetchingBlockPreview` | `Bool` | `false` | Loading indicator for preview fetch |

---

## 6. API Contracts

### 6.1 ClearSky API — Block Lists

**Base URL:** `https://public.api.clearsky.services/api/v1/anon/`

#### `GET /blocklist/{did}`
Returns accounts that `{did}` has blocked.

#### `GET /single-blocklist/{did}`
Returns accounts that have blocked `{did}` (reciprocal).

#### Pagination
Both endpoints support page-based pagination. If the response contains ≥100 entries, append `/{page}` to the URL (page starts at 1 for the first request, which is the same as no page suffix). Repeat until fewer than 100 entries are returned.

#### Response format
```json
{
  "data": {
    "blocklist": [
      {
        "did": "did:plc:abc123",
        "blocked_date": "2024-01-15T10:30:00Z"
      }
    ]
  }
}
```

#### `GET /get-did/{handle}`
Resolves a handle to a DID.

```json
{
  "data": {
    "did_identifier": "did:plc:abc123"
  }
}
```

### 6.2 Bluesky AT Protocol — Create Block Record

**Endpoint:** `com.atproto.repo.createRecord`

**Collection:** `app.bsky.graph.block`

**Request body:**
```json
{
  "repo": "{my-did}",
  "collection": "app.bsky.graph.block",
  "record": {
    "$type": "app.bsky.graph.block",
    "subject": "{target-did}",
    "createdAt": "{ISO-8601}"
  }
}
```

**Authentication:** Requires a valid session (access JWT). Uses `performAuthenticatedRequest` which handles 401 retry with JWT refresh and re-auth.

---

## 7. Service Layer Architecture

### 7.1 `LiveBlueskyClient` — Public Methods

| Method | Input | Output | Clearsky endpoint |
|--------|-------|--------|-------------------|
| `fetchBlockingCount(for:)` | `AppAccount` | `Int` | `blocklist` (totalCount only) |
| `fetchBlockedByCount(for:)` | `AppAccount` | `Int` | `single-blocklist` (totalCount only) |
| `fetchUnblockedBlockersCount(for:)` | `AppAccount` | `Int` | Both endpoints → DID set subtraction |
| `fetchBlockedActors(account:)` | `AppAccount` | `ClearskyBlocklistResult` | `blocklist` (full actors with profiles) |
| `fetchBlockedByActors(account:)` | `AppAccount` | `ClearskyBlocklistResult` | `single-blocklist` (full actors with profiles) |
| `blockActor(did:account:appPassword:)` | DID + credentials | `Void` | AT Protocol `com.atproto.repo.createRecord` |

### 7.2 `ClearskyHeartbeatService` — Availability Gate

A singleton that pings `https://public.api.clearsky.services/` every 10 seconds (HEAD request, 5s timeout). If the ping fails, `isClearskyAvailable` flips to `false`, which:

1. Disables all Clearsky-dependent features (including block back)
2. Shows a red `ClearskyBanner` at the top of the app
3. Tints the tab bar red via `.tint()` modifier

The heartbeat is started in `RULYXApp.swift` `.task` on app launch and stopped on backgrounding.

### 7.3 `DashboardCache` — On-Disk Count Cache

The `DashboardCache` persists `blockingCount` and `blockedByCount` (along with lists and profile) to a JSON file in the caches directory. This allows the dashboard to show counts immediately on next launch while fresh data loads.

**Important:** `fetchUnblockedBlockersCount` is **not** cached — it always fetches fresh DIDs from ClearSky to compute the set difference. Only the individual counts (`blockingCount`, `blockedByCount`) are cached.

---

## 8. State Machine

### 8.1 Block Back Execution (`blockBack()`)

```
ENTRY: isBlockingBack = true
         ↓
   Fetch blocked-by actors (Clearsky single-blocklist)
   Fetch blocking actors (Clearsky blocklist)
         ↓
   Compute diff: toBlock = blockedByActors ∖ blockingActors
         ↓
   toBlock.isEmpty? ──Yes──→ isBlockingBack = false → RETURN
         ↓ No
   blockBackTotal = toBlock.count
         ↓
   FOR batchStart in stride(0, total, 5):
       batch = toBlock[batchStart ..< min(batchStart+5, total)]
         ↓
       withTaskGroup(of: Bool.self):
           FOR each actor in batch (parallel):
               blockActor(did)
               return success/failure
           FOR each result:
               blockBackCompleted++
               success ? blockBackSuccessCount++ : blockBackFailureCount++
         ↓
       IF more batches remain:
           sleep(300ms)
         ↓
   END FOR
         ↓
   showBlockBackResult = true
   fetchBlockCounts()  // refresh
         ↓
   sleep(4s)
   showBlockBackResult = false
         ↓
EXIT: isBlockingBack = false
```

### 8.2 Error Recovery

| Condition | Behavior |
|-----------|----------|
| `toBlock.isEmpty` | Silent return (nothing to do) |
| Fetch fails (first error before any individual block attempt) | `blockBackError = error.localizedDescription`, `isBlockingBack = false` |
| Partial failures during batching | Individual failures are counted in `blockBackFailureCount`; batching continues |
| Whole batch fetch succeeds but some individual blocks fail | Result summary shows mixed success/failure |
| `fetchBlockCounts()` fails at the end | Error is silently logged (counts stay stale) |

---

## 9. Error Handling

### 9.1 Guard: Clearsky Unavailable

```swift
private func guardClearskyAvailable() throws {
    guard clearskyHeartbeat.isClearskyAvailable else {
        throw BlueskyAPIError.server("ClearSky is temporarily unavailable")
    }
}
```

Called at the top of `fetchClearskyDIDs()`, `fetchClearskyActors()`, `resolveHandleToDID()`, and `fetchUnblockedBlockersCount()`. If Clearsky is down, the error propagates to the caller.

### 9.2 Guard: Missing Credentials

Both `fetchBlockCounts()` and `fetchBlockPreview()` return early if `accountStore.activeAccount` or `accountStore.appPassword(for:)` is nil.

### 9.3 Guard: Own-Profile Check

Both fetch methods return early if `isOwnProfile == false || showBetaFeatures == false`.

### 9.4 Network Errors

All `try? await` usage:
- `fetchBlockCounts()` → `try await` inside a `do/catch` that logs the error
- `fetchBlockPreview()` → same pattern
- `blockBack()` → `do/catch` with a branching path: if no blocks completed, sets `blockBackError`; if partial, shows result summary with partial data

### 9.5 Timeouts

All Clearsky HTTP requests use `request.timeoutInterval = 30`.

---

## 10. Concurrency Model

### 10.1 Three Concurrent Fetches (Counts)

```swift
async let b = blueskyClient.fetchBlockedByCount(for: account)
async let k = blueskyClient.fetchBlockingCount(for: account)
async let u = blueskyClient.fetchUnblockedBlockersCount(for: account)
(blockedByCount, blockingCount, unblockedBlockersCount) = try await (b, k, u)
```

All three run in parallel. `fetchUnblockedBlockersCount` itself fires two more parallel requests (for `blocklist` and `single-blocklist` DIDs).

### 10.2 Two Concurrent Fetches (Preview / Execution)

```swift
async let blockedByResult = blueskyClient.fetchBlockedByActors(account: account, appPassword: appPassword)
async let blockedResult = blueskyClient.fetchBlockedActors(account: account, appPassword: appPassword)
let (blockedByActors, blockedActors) = try await (blockedByResult.actors, blockedResult.actors)
```

### 10.3 Batched Concurrent Blocks

Blocks are executed in **batches of 5** using `withTaskGroup(of: Bool.self)`. Each actor in a batch gets its own child task. The group collects results as they complete. A **300ms delay** is inserted between batches to avoid rate-limiting.

### 10.4 UI State Updates

All `@State` mutations happen on `@MainActor` (the default for SwiftUI views). The `blockBack()` function mutates state directly inside the `for await success in group` loop, which triggers reactive UI updates for the progress bar on each completion.

---

## 11. Localization Keys

All 20 keys (full set across all 16 language files):

### Section & Rows
| Key | English value |
|-----|---------------|
| `profile.block_back.section` | "Block Back" |
| `profile.block_back.blocking` | "Blocking" |
| `profile.block_back.blocked_by` | "Blocked By" |
| `profile.block_back.unblocked` | "Accounts not yet blocked" |

### Loading
| Key | English value |
|-----|---------------|
| `profile.block_back.loading` | "Loading block info…" |

### Action
| Key | English value |
|-----|---------------|
| `profile.block_back.action` | "Block Back" |

### Progress
| Key | English value |
|-----|---------------|
| `profile.block_back.progress` | "Blocking back {completed}/{total}…" |

### Completion
| Key | English value |
|-----|---------------|
| `profile.block_back.all_clear` | "You block all accounts that block you" |
| `profile.block_back.none_blocking` | "No accounts are blocking you." |

### Confirmation Dialogs
| Key | English value |
|-----|---------------|
| `profile.block_back.confirm.first.title` | "Block Back" |
| `profile.block_back.confirm.first.message` | "Block {count} account(s) that block you but aren't blocked back?" |
| `profile.block_back.confirm.second.title` | "Are you sure?" |
| `profile.block_back.confirm.second.message` | "This cannot be undone." |

### Result Summary
| Key | English value |
|-----|---------------|
| `profile.block_back.result` | "{success} blocked, {fail} failed" |
| `profile.block_back.result_success` | "All {count} accounts blocked" |

### Preview Sheet
| Key | English value |
|-----|---------------|
| `profile.block_back.preview.title` | "Accounts to Block Back" |
| `profile.block_back.preview.count` | "{count} account(s) that block you but are not blocked back" |
| `profile.block_back.preview.empty` | "No accounts to block back" |
| `profile.block_back.preview.blocks_me` | "Blocks me" |
| `profile.block_back.preview.not_blocked` | "Not blocked back" |

---

## 12. Testing Guide

### 12.1 Unit Tests

| Test File | Tests |
|-----------|-------|
| `ListsViewModelTests.swift` | Initial state (counts nil), load fetches blocking count, error handling falls back to nil |
| `InfrastructureServiceTests.swift` | DashboardCache persistence of blockingCount/blockedByCount |
| `ViewModelTests.swift` | ListsViewModel initial state and nil-account load |

### 12.2 Preview Mock Data

The `PreviewBlueskyClient` provides mock implementations:

```swift
override func fetchBlockedActors(...) async throws -> ClearskyBlocklistResult {
    // Returns 2 mock actors: "Spam Account" and "Troll Account"
}
override func fetchBlockedByActors(...) async throws -> ClearskyBlocklistResult {
    // Returns empty list
}
override func fetchBlockingCount(for:) async throws -> Int { 2 }
override func fetchBlockedByCount(for:) async throws -> Int { 0 }
override func fetchUnblockedBlockersCount(for:) async throws -> Int { 0 }
override func blockActor(did:account:appPassword:) async throws {
    // Simulates 120ms delay
}
```

### 12.3 Edge Cases to Test

| Scenario | Expected behavior |
|----------|-------------------|
| `blockingDIDs` is a superset of `blockedByDIDs` | `unblockedBlockersCount` = 0, "All clear" shown |
| Both sets are empty | `unblockedBlockersCount` = 0, "No accounts are blocking you" shown |
| Single large set (>100 entries) | Pagination works correctly, all pages fetched |
| Network failure during count fetch | Logged error, counts stay nil, no crash |
| Network failure during preview fetch | Preview opens empty, error logged |
| Network failure during block execution | Partial results tracked, summary shown |
| Clearsky goes down mid-operation | Next `guardClearskyAvailable()` call throws |
| User switches accounts during block-back | The `account` param is captured at call time, no race condition |
| `blockBack()` called with zero `toBlock` | Silent return, `isBlockingBack = false` |

---

## 13. Security & Privacy Considerations

### 13.1 ClearSky is a Third-Party Service

All block data comes from ClearSky's public API (`public.api.clearsky.services`). No authentication is required to query ClearSky. The app does not send any credentials to ClearSky — only a DID is sent as a path parameter.

### 13.2 Blocking Uses AT Protocol Sessions

Executing blocks requires an authenticated Bluesky session. The `blockActor()` method uses `performAuthenticatedRequest`, which handles 401 retry with JWT refresh and re-authentication using the stored app password. Sessions and app passwords are stored in the Keychain via `KeychainService`.

### 13.3 DID Resolution

DIDs are resolved using ClearSky's `get-did` endpoint or taken directly from `AppAccount.did`. No raw handles are sent to the AT Protocol for block creation — only DIDs.

### 13.4 No Data Sent Off-Device for Block Calculation

The DID set subtraction (`blockedByDIDs.subtracting(blockingDIDs)`) is performed entirely on-device. Only the raw DID lists are fetched from ClearSky.

---

## 14. Performance Considerations

### 14.1 Pagination Throughput

The ClearSky pagination loop makes sequential requests (one page at a time). For users with very large block lists (thousands), this could take many seconds. Consider implementing parallel page fetching as an optimization.

### 14.2 Profile Resolution Bottleneck

`fetchClearskyActors()` calls `resolveProfiles()` which makes batched requests to `app.bsky.actor.getProfiles` (25 DIDs per batch). For large lists, this adds significant latency. The DID-only variant `fetchClearskyDIDs()` skips this, which is why `fetchUnblockedBlockersCount()` uses it instead.

### 14.3 Batch Size Tuning

The `batchSize = 5` for concurrent block operations is conservative. Increasing it could speed up large operations at the cost of higher rate-limit risk. The 300ms inter-batch delay is a safety measure.

### 14.4 Cache Expiry

`DashboardCache` persists to disk but has no expiry mechanism — it's overwritten on each successful `load()`. Cached data is used only as an initial display optimization and is immediately replaced when fresh data arrives.

---

## 15. Dependencies

### 15.1 External Services

| Service | Purpose | Endpoint |
|---------|---------|----------|
| ClearSky API | Block list retrieval (who I block, who blocks me) | `public.api.clearsky.services` |
| Bluesky AT Protocol | Block record creation | `com.atproto.repo.createRecord` on user's PDS |
| Bluesky AT Protocol | Profile resolution | `app.bsky.actor.getProfiles` on `public.api.bsky.app` |

### 15.2 Internal Dependencies

| Component | Used by | Reason |
|-----------|---------|--------|
| `LiveBlueskyClient` | `BlueskyProfileView` | All Clearsky and AT Protocol calls |
| `BlueskySessionService` | `LiveBlueskyClient` | Authenticated request handling (401 retry) |
| `ClearskyHeartbeatService` | `LiveBlueskyClient`, `RootView` | Availability gate |
| `AccountStore` | `BlueskyProfileView` | Active account + app password retrieval |
| `DashboardCache` | `ListsViewModel` | Count persistence (not directly used by block back) |
| `KeychainService` | `BlueskySessionService` | Session and app password storage |

### 15.3 File Reference

| File | Absolute path |
|------|--------------|
| BlueskyProfileView.swift | `Sources/Features/Lists/BlueskyProfileView.swift` |
| LiveBlueskyClient.swift | `Sources/Domain/Services/LiveBlueskyClient.swift` |
| BlueskyAPIDTOs.swift | `Sources/Domain/Services/BlueskyAPIDTOs.swift` |
| BlueskyActor.swift | `Sources/Domain/Models/BlueskyActor.swift` |
| ClearskyHeartbeatService.swift | `Sources/Domain/Services/ClearskyHeartbeatService.swift` |
| DashboardCache.swift | `Sources/Domain/Services/DashboardCache.swift` |
| PreviewBlueskyClient.swift | `Sources/Domain/Services/PreviewBlueskyClient.swift` |
| en.json | `Sources/Shared/Localizations/en.json` |
| AppDependencies.swift | `Sources/App/AppDependencies.swift` |
| RootView.swift | `Sources/App/RootView.swift` |
| RULYXApp.swift | `Sources/App/RULYXApp.swift` |
| BlueskyProfileView.swift | `Tests/RULYXTests/ListsViewModelTests.swift` |
| BlueskyProfileView.swift | `Tests/RULYXTests/ViewModelTests.swift` |
| BlueskyProfileView.swift | `Tests/RULYXTests/InfrastructureServiceTests.swift` |
