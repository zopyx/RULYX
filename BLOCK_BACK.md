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

The **Block Back** feature allows a Bluesky user to mass-block all accounts that block them but that they have not yet blocked back. It works with the AT Protocol alone: "Blocking" is read from the account's **own repository** (`app.bsky.graph.block` records), "Blocked by" from the **Constellation backlink index** (the same records, seen from the linked side), and list data from the index plus the public **Bluesky AppView**. It is gated behind both an **own-profile check** and the **`showBetaFeatures`** user-defaults flag.

> **History:** until October 2026 the feature read block data from the third-party ClearSky API as its primary source, with the own repo and the index as fallbacks. The service was suspended (`503 Service Suspended`) and has been removed from the app entirely — every direction now has exactly one source.

The feature has five distinct phases:

| Phase | What happens | UI state |
|-------|-------------|----------|
| **Idle** | Block counts are fetched on profile load: own repo (blocking) + backlink index (blocked by) | Three `LabeledContent` rows showing Blocking / Blocked by / Accounts not yet blocked |
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
10. **AC-10:** Each direction reads exactly one source (own repo / Constellation index / AppView) and the count is derived from the same records the list renders, so the dashboard and the detail screen cannot disagree. A failing source surfaces as an error; a cached payload is served when one exists. No third-party availability gate and no warning banner exist any more.

---

## 3. UX Flow

```mermaid
flowchart TD
    A[Own Profile Loads] --> B[fetchBlockCounts]
    B --> C[Own repo: block records<br>Index: backlink records]
    C -->|both fail| D[Counts stay nil<br>error logged]
    C -->|data| E[Display counts<br>Blocking | Blocked by |<br>Accounts not yet blocked]
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
    var blockedDate: Date?   // from the block record's createdAt, or its TID record key (index side)
    var description: String?
}
```

### 5.2 `BlocklistResult`

```swift
struct BlocklistResult {
    let actors: [BlueskyActor]
    let totalCount: Int      // the source's own total (repo record count / index total)
}
```

### 5.3 Blocklist DTOs

```swift
/// One blocker from the Constellation index (or one blocked account, mapped from the repo).
struct BlocklistEntry {
    let did: String
    let blockedDate: String   // ISO 8601; from the record's createdAt or its TID key
}

/// One `app.bsky.graph.block` record from the account's own repo.
struct RepoBlockRecord: Codable {
    let did: String            // the record's `subject`
    let createdAt: String?
}

/// One row of the "Listed on" screen.
struct ListedOnListEntry {
    let name: String
    let description: String?
    let did: String            // the list owner
    let url: String            // the list AT-URI
    let createdDate: String
    let dateAdded: String      // from the listitem record key
}
```

### 5.4 View State Properties

All stored as `@State` in `BlueskyProfileView`:

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `blockingCount` | `Int?` | `nil` | Number of accounts I block (own repo block records) |
| `blockedByCount` | `Int?` | `nil` | Number of accounts that block me (index ``getBacklinks`` total) |
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

### 6.1 Own repo API — "Blocking"

**Base URL:** the account's PDS (`AppAccount.pdsURL`, e.g. `https://bsky.social` or
`https://eurosky.social`) — no third party in the path.

#### `GET /xrpc/com.atproto.repo.listRecords?repo={did}&collection=app.bsky.graph.block&limit=100`

Returns the account's own `app.bsky.graph.block` records: each record's `subject` **is** a
blocked account, so the record set is the blocklist.

#### Pagination
Cursor-based: pass the returned `cursor` back until it is absent (the protocol caps
`limit` at 100). The walk is capped at 100 pages and logged when it truncates.

#### Response format
```json
{
  "records": [
    {
      "uri": "at://did:plc:me/app.bsky.graph.block/3lgxunk3mqu2z",
      "value": {
        "$type": "app.bsky.graph.block",
        "subject": "did:plc:abc123",
        "createdAt": "2024-01-15T10:30:00Z"
      }
    }
  ],
  "cursor": "3lgxunk3mqu2z"
}
```

#### Handle resolution

Handles are resolved with the authoritative AT Protocol call
`com.atproto.identity.resolveHandle` (`https://public.api.bsky.app`) — an account's DID is
read from `AppAccount.did` whenever it is known, so the call is rare.

### 6.2 Constellation API — Block Backlinks (the "Blocked by" source)

"Blocked by" cannot be read from any single repo: the answering records live in the
blockers' repositories, and a repo can only enumerate what its own owner wrote. The
Constellation backlink index (`https://constellation.microcosm.blue`) crawls the AT
Protocol firehose and indexes every link between records — including the `subject` of each
`app.bsky.graph.block` record — so it can answer "which records point at this DID?".

#### `GET /xrpc/blue.microcosm.links.getBacklinks?subject={did}&source=app.bsky.graph.block:subject`

| Parameter | Value |
|-----------|-------|
| `subject` | the DID whose blockers are wanted |
| `source` | `app.bsky.graph.block:subject` — collection + JSON path of the linking record |
| `limit` | upper bound only: the server returns *fewer* records per page than requested (observed ≈ 70 % of `limit`), max `100` |
| `cursor` | opaque, sequential; follow until it is absent |

```json
{
  "total": 11004,
  "records": [
    { "did": "did:plc:abc123", "collection": "app.bsky.graph.block", "rkey": "3mwu2mkp2zk2v" }
  ],
  "cursor": "fbcc37fbd00cfbc737"
}
```

- `total` is exact and independent of the page size, so the "Blocked by" count costs a
  single request (`limit=1`).
- Records carry no `createdAt`: the block date is decoded from the TID record key
  (`AtProtoTid`), verified to within one second of the record's `createdAt`.
- Pages cannot be fetched in parallel (the cursor chains). The client caps a walk at
  50 pages and always reports the API's own `total`, so counts stay exact even when the
  actor list is truncated.
- A walk takes ~0.4 s per page, so results are cached under
  `constellation/blocked-by/{did}` in `BlueskyAPICache` and the last good payload is
  served when a refresh fails.

#### `GET /xrpc/blue.microcosm.links.getManyToManyCounts?subject={did}&source=app.bsky.graph.listitem:subject&pathToOther=list`

Answers "Listed on": a membership is an `app.bsky.graph.listitem` record that links the
listed profile (`subject`) **and** its list (`list`), so grouping the membership records
by their secondary link yields one entry per list.

```json
{
  "counts_by_other_subject": [
    { "subject": "at://did:plc:owner/app.bsky.graph.list/3kushlzczl42u", "total": 2, "distinct": 2 }
  ],
  "cursor": "0a33303036343434313335"
}
```

- One entry per **distinct list**, not per membership record: a profile re-added to a list
  has one record per addition (`total` > 1 for that list). The count is therefore the
  number of entries, not the number of records.
- Pages hold at most 100 entries, so the counter must follow the cursor. Results are
  cached under `constellation/listed-on/{did}` together with the list AT-URIs.

#### `GET /xrpc/blue.microcosm.links.getManyToMany?subject={did}&source=app.bsky.graph.listitem:subject&pathToOther=list`

The detail variant of the query above: same parameters, but each item carries its **linking
record** instead of only an aggregate.

```json
{
  "items": [
    {
      "linkRecord": { "did": "did:plc:owner", "collection": "app.bsky.graph.listitem", "rkey": "3lgxunk3mqu2z" },
      "otherSubject": "at://did:plc:owner/app.bsky.graph.list/3kushlzczl42u"
    }
  ],
  "cursor": "03322c30"
}
```

- `otherSubject` is the list AT-URI, `linkRecord.rkey` is a TID — i.e. the date the profile
  was added, which is the `date_added` value the screen shows. Memberships are cached under
  `constellation/listed-on-memberships/{did}`.
- The list **metadata** (name, description) is not in the index. It is fetched from the
  public AppView **per list owner**, not per list:
  `app.bsky.graph.getLists?actor={ownerDID}&limit=100` returns up to 100 lists of one repo
  in a single request, so the ~107 owners behind ~150 lists cost ~107 requests instead of
  150 — cached per owner under `appview/lists/{ownerDID}` (public data, shared across
  accounts). A list the owner's page does not contain is retried once via
  `app.bsky.graph.getList?list={uri}`; a list that resolves nowhere has been deleted and is
  dropped from the screen. See `ListedOnListResolver`.

### 6.3 Source policy

Every direction has exactly **one** source; there is no fallback chain any more.

| Operation | Source |
|-----------|--------|
| "Blocking" (own blocklist) count / list / DIDs | own repo — `com.atproto.repo.listRecords` on `app.bsky.graph.block` |
| "Blocked by" count / actor list / DIDs | Constellation backlinks (`getBacklinks`, `total` is exact) |
| "Listed on" count | Constellation `getManyToManyCounts` (distinct lists) |
| "Listed on" detail (screen) | Constellation `getManyToMany` + AppView `getLists`/`getList` per owner |
| Block Back execution, preview, diff | the two blocklist rows above (repo + index) |

Why each one is the only source: the own repo is the authoritative record of what its
owner blocked, and the index cannot enumerate it (`getBacklinks`' `did` filter only
narrows links that point **at** a subject); conversely no repo lists its incoming
blocks, so "Blocked by" needs the index. The account's own repository is the authoritative answer, and
`com.atproto.repo.listRecords?repo={did}&collection=app.bsky.graph.block` reads it without
authentication:

- Paginated at 100 records per page, cursor followed to the end (capped at 100 pages),
  cached under `repo/blocklist/{did}`, last good payload served when a refresh fails.
- The client reads the account's PDS (`AppAccount.pdsURL`), so it is **unpinned** on
  purpose: `HTTPClient.defaultPinnedHashes` covers the app's fixed API hosts only, and the
  pinning delegate cancels any chain without a matching pin.
- The dashboard count (`fetchBlockingCount`) and the detail list (`fetchBlockedActors`)
  both fall back to this read, so the two numbers cannot diverge.

Each read serves its own cached payload when a refresh fails (repo under
`repo/blocklist/{did}`, index under `constellation/blocked-by/{did}`), and surfaces the
error when there is nothing cached. Both directions are keyed on the same
`app.bsky.graph.block` record, so the two sets mean the same thing. Cancellation always
propagates — it is never swallowed by a cache fallback.

### 6.4 Bluesky AT Protocol — Create Block Record

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

| Method | Input | Output | Source |
|--------|-------|--------|--------|
| `fetchBlockingCount(for:forceRefresh:)` | `AppAccount` | `Int` | own repo record count (cached) |
| `fetchBlockedByCount(for:)` | `AppAccount` | `Int` | index `total` (single request) |
| `fetchUnblockedBlockersCount(for:)` | `AppAccount` | `Int` | repo vs. index DID set subtraction |
| `fetchBlockedActors(account:)` | `AppAccount` | `BlocklistResult` | own repo records + profiles resolved best-effort |
| `fetchBlockedByActors(account:)` | `AppAccount` | `BlocklistResult` | index backlinks + profiles resolved best-effort |
| `fetchBlockedDIDs(for:)` | `AppAccount` | `Set<String>` | own repo (cached) |
| `fetchBlockerDIDs(for:)` | `AppAccount` | `Set<String>` | index backlinks (cached) |
| `fetchListedOnCount(handle:did:)` | handle + DID | `Int` | index `getManyToManyCounts` (cached) |
| `fetchListedOnLists(handle:did:)` | handle + DID | `[ListedOnListEntry]` | index `getManyToMany` + AppView `getLists` per owner |
| `blockActor(did:account:appPassword:)` | DID + credentials | `Void` | AT Protocol `com.atproto.repo.createRecord` |

### 7.2 Sources — `ConstellationClient`, `AtProtoRepoClient`, `ListedOnListResolver`

`ConstellationClient` (`Sources/Domain/Services/ConstellationClient.swift`) owns every
Constellation call: the exact blocker count (one request), the DIDs, the paginated
backlink walk with its cache, the actor list with best-effort profile resolution, and the
"Listed on" list count (`getManyToManyCounts`). `LiveBlueskyClient`'s blocklist entry
points delegate to it — see §6.3.

`AtProtoRepoClient` (`Sources/Domain/Services/AtProtoRepoClient.swift`) owns the read of
an account's own `app.bsky.graph.block` records over `com.atproto.repo.listRecords`: the
pagination loop, the deduplication by subject, the cache under `repo/blocklist/{did}` and
the stale-cache fallback. It is unauthenticated and pins nothing (the PDS host varies per
account). `BlueskyProfileService.fetchExistingBlockedDIDs` performs the same read on the
authenticated path and is a candidate to fold into this client.

`ListedOnListResolver` (`Sources/Domain/Services/ListedOnListResolver.swift`) turns the
index memberships into the `ListedOnListEntry` rows the "Listed on" screen renders: it
groups the wanted lists by their owning repo, fetches one AppView page per owner — all
owners at once, with throttled (`429`/`5xx`) responses retried per owner so the wide fan-out
cannot silently drop a list — retries unresolved lists individually and decodes the membership
date from the listitem record key. It is deliberately best effort — a list that no longer
resolves is dropped, because the screen is an enrichment of the index walk.

### 7.3 No availability gate

There is no heartbeat service, no `isClearskyAvailable` flag, no warning banner and no red
tint any more: the sources are the AT Protocol itself (own repo, AppView) and the public
index, so there is no third-party service to poll. A failing source is reported per call
(cached payload if one exists, otherwise the error), and the block rows keep rendering.

### 7.4 `DashboardCache` — On-Disk Count Cache

The `DashboardCache` persists `blockingCount` and `blockedByCount` (along with lists and profile) to a JSON file in the caches directory. This allows the dashboard to show counts immediately on next launch while fresh data loads.

**Important:** `fetchUnblockedBlockersCount` is **not** cached — it computes the set difference from the two DID reads (which are themselves cached) so a just-executed block-back is reflected immediately. Only the individual counts (`blockingCount`, `blockedByCount`) are persisted by the dashboard cache.

---

## 8. State Machine

### 8.1 Block Back Execution (`blockBack()`)

```
ENTRY: isBlockingBack = true
         ↓
   Fetch blocked-by actors (index backlinks)
   Fetch blocking actors (own repo records)
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

### 9.1 No availability guard

There is no `guardClearskyAvailable()` any more. Each source read either succeeds, serves its
cached payload, or throws: the PDS/library errors surface as `BlueskyAPIError`, and the
caller (`BlueskyProfileActionsViewModel`) shows the error row while keeping the counts it
already had. `CancellationError` is deliberately rethrown rather than turned into a cache
fallback.

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

All blocklist HTTP requests (repo, index, AppView) use `request.timeoutInterval = 30`.

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
override func fetchBlockedActors(...) async throws -> BlocklistResult {
    // Returns 2 mock actors: "Spam Account" and "Troll Account"
}
override func fetchBlockedByActors(...) async throws -> BlocklistResult {
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
| The index or the PDS fails mid-operation | The call throws (or serves its cached payload) and the error row appears |
| User switches accounts during block-back | The `account` param is captured at call time, no race condition |
| `blockBack()` called with zero `toBlock` | Silent return, `isBlockingBack = false` |

---

## 13. Security & Privacy Considerations

### 13.1 Third-Party Data Sources

Three public endpoints are used, none of which receives credentials: the account's own PDS
(`com.atproto.repo.listRecords`, unauthenticated read of the account's own public records),
the Constellation index (`constellation.microcosm.blue`, queried by DID) and the Bluesky
AppView (`public.api.bsky.app`, list metadata). "Blocking" comes from the user's own repo
and is therefore not a third-party copy at all; "Blocked by" and "Listed on" necessarily
consult the public index.

### 13.2 Blocking Uses AT Protocol Sessions

Executing blocks requires an authenticated Bluesky session. The `blockActor()` method uses `performAuthenticatedRequest`, which handles 401 retry with JWT refresh and re-authentication using the stored app password. Sessions and app passwords are stored in the Keychain via `KeychainService`.

### 13.3 DID Resolution

DIDs are taken directly from `AppAccount.did`, or resolved with the AT Protocol's `com.atproto.identity.resolveHandle` when only a handle is known. No raw handles are sent for block creation — only DIDs.

### 13.4 No Data Sent Off-Device for Block Calculation

The DID set subtraction (`blockedByDIDs.subtracting(blockingDIDs)`) is performed entirely on-device. Only raw DID lists (<span style="white-space:nowrap">`app.bsky.graph.block`</span> members) leave the device to fetch the two sides.

---

## 14. Performance Considerations

### 14.1 Pagination Throughput

Both walks are sequential by contract: the index chains its cursors (`getBacklinks` pages cannot be requested in parallel) and the repo walk follows the PDS cursor. A large blocklist (thousands of records) therefore takes several seconds on a cold cache; results are cached afterwards (`repo/blocklist/{did}`, `constellation/blocked-by/{did}`).

### 14.2 Profile Resolution Bottleneck

`fetchBlockedActors()`/`fetchBlockedByActors()` resolve profiles in 25-DID batches and drop a DID whose profile does not resolve — for large lists this dominates the latency. The two paths differ in how wide they fan out: the repo side (`LiveBlueskyClient.resolveProfilesBestEffort`) starts every batch at once, while the index side (`ConstellationClient.resolveProfilesBestEffort`) keeps five batches (125 DIDs) in flight. The DID-only reads `fetchBlockedDIDs()`/`fetchBlockerDIDs()` skip profile resolution entirely — which is why `fetchUnblockedBlockersCount()` and the counts use those.

### 14.3 "Listed on" Fan-Out

`ListedOnListResolver` used to query list owners in rounds of five, which turned the ~100 owners behind a well-listed profile into ~20 sequential rounds — the dominant cost of the screen. All owners are now queried at once; a throttled (`429`) or failing (`5xx`) response is retried per owner with a short backoff (`maxFetchAttempts = 3`), so the wide fan-out cannot silently drop a list. The membership walk before it stays sequential: the index chains its cursors. The sheet's member-count requests already run unbounded (one per list).

### 14.4 Batch Size Tuning

The `batchSize = 5` for concurrent block operations is conservative. Increasing it could speed up large operations at the cost of higher rate-limit risk. The 300ms inter-batch delay is a safety measure.

### 14.5 Cache Expiry

`DashboardCache` persists to disk but has no expiry mechanism — it's overwritten on each successful `load()`. Cached data is used only as an initial display optimization and is immediately replaced when fresh data arrives.

---

## 15. Dependencies

### 15.1 External Services

| Service | Purpose | Endpoint |
|---------|---------|----------|
| Constellation index | "Blocked by" backlinks, "Listed on" memberships | `constellation.microcosm.blue` |
| Own PDS | "Blocking" (the account's own block records) | `com.atproto.repo.listRecords` on `AppAccount.pdsURL` |
| Bluesky AppView | List metadata for "Listed on", profiles, identity | `public.api.bsky.app` |
| Bluesky AT Protocol | Block record creation | `com.atproto.repo.createRecord` on user's PDS |

### 15.2 Internal Dependencies

| Component | Used by | Reason |
|-----------|---------|--------|
| `LiveBlueskyClient` | `BlueskyProfileView` | All blocklist and AT Protocol calls |
| `BlueskySessionService` | `LiveBlueskyClient` | Authenticated request handling (401 retry) |
| `AtProtoRepoClient` | `LiveBlueskyClient` | Own-repo reads ("Blocking") |
| `ConstellationClient` | `LiveBlueskyClient` | Index reads ("Blocked by", "Listed on") |
| `ListedOnListResolver` | `LiveBlueskyClient` | Memberships + AppView metadata for "Listed on" |
| `AccountStore` | `BlueskyProfileView` | Active account + app password retrieval |
| `DashboardCache` | `ListsViewModel` | Count persistence (not directly used by block back) |
| `KeychainService` | `BlueskySessionService` | Session and app password storage |

### 15.3 File Reference

| File | Absolute path |
|------|--------------|
| BlueskyProfileView.swift | `Sources/Features/Lists/BlueskyProfileView.swift` |
| LiveBlueskyClient.swift | `Sources/Domain/Services/LiveBlueskyClient.swift` |
| ConstellationClient.swift | `Sources/Domain/Services/ConstellationClient.swift` |
| ConstellationEndpoints.swift | `Sources/Domain/Services/ConstellationEndpoints.swift` |
| AtProtoRepoClient.swift | `Sources/Domain/Services/AtProtoRepoClient.swift` |
| ListedOnListResolver.swift | `Sources/Domain/Services/ListedOnListResolver.swift` |
| HTTPClient.swift (certificate pins) | `Sources/Domain/Services/HTTPClient.swift` |
| BlueskyAPIDTOs.swift | `Sources/Domain/Services/BlueskyAPIDTOs.swift` |
| BlueskyActor.swift | `Sources/Domain/Models/BlueskyActor.swift` |
| BlueskyBlocklistServicing.swift | `Sources/Domain/Services/Protocols/BlueskyBlocklistServicing.swift` |
| BlocklistDTOs.swift | `Sources/Domain/Models/DTOs/BlocklistDTOs.swift` |
| MockBlocklistService.swift | `Tests/TestUtilities/MockBlocklistService.swift` |
| DashboardCache.swift | `Sources/Domain/Services/DashboardCache.swift` |
| PreviewBlueskyClient.swift | `Sources/Domain/Services/PreviewBlueskyClient.swift` |
| en.json | `Sources/Shared/Localizations/en.json` |
| AppDependencies.swift | `Sources/App/AppDependencies.swift` |
| RootView.swift | `Sources/App/RootView.swift` |
| RULYXApp.swift | `Sources/App/RULYXApp.swift` |
| BlueskyProfileView.swift | `Tests/RULYXTests/ListsViewModelTests.swift` |
| BlueskyProfileView.swift | `Tests/RULYXTests/ViewModelTests.swift` |
| BlueskyProfileView.swift | `Tests/RULYXTests/InfrastructureServiceTests.swift` |
