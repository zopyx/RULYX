# Rulyx — User Guide

> Bluesky moderation made easy

Rulyx is a native iOS app for managing Bluesky moderation — lists, bulk operations, profile inspection, and follower/following management.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Accounts](#2-accounts)
3. [The Main Dashboard](#3-the-main-dashboard)
4. [Lists](#4-lists)
5. [Profile Inspector](#5-profile-inspector)
6. [Relationships](#6-relationships)
7. [Bulk Operations](#7-bulk-operations)
8. [Moderation Tools](#8-moderation-tools)
9. [Analytics & Reports](#9-analytics--reports)
10. [Advanced Features](#10-advanced-features)
11. [FAQ & Troubleshooting](#11-faq--troubleshooting)

---

## 1. Getting Started

### What you need

- An iPhone running iOS 17.0 or later
- A Bluesky account with an [app password](https://bsky.app/settings/app-passwords)

### First Launch

1. Open Rulyx
2. Tap **Add Account** to enter your Bluesky handle and app password
3. Choose your provider:
   - **Bluesky** — standard `bsky.social` accounts
   - **Eurosky** — `eurosky.social` accounts
   - **Other** — custom PDS providers (see [Multi-Provider Support](#10-advanced-features))

> 💡 **App passwords** are generated in Bluesky Settings → App Passwords. Never use your main password.

---

## 2. Accounts

### Adding an Account

![Account Setup Screen]

1. Tap the account chip in the top-left corner of the main screen
2. Tap **+** (Add Account)
3. Select your **Provider** (Bluesky, Eurosky, or Other)
4. Enter your **Handle** and **App Password**
5. Tap **Save**

### Account Labels

Organize accounts with labels like Work, Personal, or Community:

1. Open the **Account Switcher** (tap account chip)
2. Long-press or use the context menu on any account
3. Tap **Edit Label**
4. Choose a suggested label or type your own

### Switching Accounts

- Tap the account chip in the top-left to open the switcher
- Tap any account to switch — lists and data reload automatically

### Removing an Account

Swipe left on an account in the switcher and tap **Remove**. All credentials are securely deleted.

---

## 3. The Main Dashboard

![Main Dashboard]

The main screen shows:

| Section | Content |
|---------|---------|
| **Account Card** | Active account avatar, handle, and display name |
| **Relationships** | Follower/following/blocking counts — tap to view |
| **Moderation Lists** | Lists grouped by type |
| **Lists** | Regular curation lists |

### Quick Actions

- **Refresh** — pull down or tap the ↻ button
- **Create List** — tap **+** next to any section header
- **Bulk Lookup** — tap the ellipsis (⋯) menu → Bulk Lookup
- **Dashboard** — tap ⋯ → Dashboard for analytics

### Search and Filter

Use the search field at the top to filter lists by name or description.

---

## 4. Lists

### Creating a List

1. Tap **+** next to a section header (Moderation Lists or Lists)
2. Enter a name and optional description
3. Or tap **Choose from Templates** for pre-built options:
   - Spam Watch · Reply Guys · Trusted Sources
   - Community Core · New Reports · Emergency Block

### Managing List Members

Tap any list to open its detail view:

- **Search** — find accounts in the member list
- **Add** — search Bluesky and add accounts
- **Import** — paste handles/DIDs/URLs in bulk
- **Remove** — select members and remove them
- **Export** — share the member list as CSV

### Comparing Lists

1. Open a list and scroll to the **Compare & Transfer** section
2. Select another list to compare
3. View overlap, differences, and export the diff

### Merging Lists

1. In the comparison section, use **Copy Members** or **Move Members**
2. Selected members are batch-copied/moved with progress tracking

### Splitting Lists

Use conditional filtering to split lists by:
- Young accounts (< 4 weeks old)
- Handle pattern matching

### List Statistics

Each list displays:
- Total member count
- Snapshot history count
- Growth trend (comparing oldest vs newest snapshot)

### Subscribing to Third-Party Lists

1. Open a list and tap the **Subscribe** button (link icon) in the toolbar
2. Paste the AT URI of the list to subscribe to
3. Tap **Fetch** to load all members
4. Tap **Add All** to copy members into your list

Useful for subscribing to shared moderation lists from trusted moderators.

### Snapshot History

Snapshots are captured automatically whenever you view a list or complete a bulk operation:

- Each snapshot records the full member list
- Compare two snapshots to see what changed
- Up to 12 snapshots are retained per list
- Use the pickers to select which snapshots to compare

---

## 5. Profile Inspector

![Profile Inspector]

Access the profile inspector via **⋯ → Bulk Lookup**, or tap any account handle throughout the app.

### Inspecting a Profile

1. Enter a handle, DID, or Bluesky profile URL
2. Tap **Lookup** or press Enter
3. View the comprehensive profile report

### What You See

| Section | Content |
|---------|---------|
| **Profile** | Avatar, display name, handle, description |
| **Stats** | Followers, following, posts, lists, starter packs |
| **Moderation** | Block/mute toggles (one-tap, real-time) |
| **Moderation Lists** | List memberships — add or remove |
| **Account Info** | Handle, DID, join date, labels |
| **Handle History** | Past handle changes from PLC directory |
| **Actions** | Block all followers, add/edit notes |
| **Open in Bluesky** | Opens the profile in the Bluesky app |

### Block / Mute Toggles

Block and mute are instant one-tap toggles:
- Toggle **Block** on → account is blocked immediately
- Toggle **Mute** on → account is muted immediately
- Toggle off to reverse

No confirmation dialogs — designed for power users.

### Profile Notes

Attach private notes to any profile:
1. In the profile view, tap **Add Note** in the Actions section
2. Type your note (stored locally on device only)
3. Tap **Save** — notes persist across app restarts

---

## 6. Relationships

### Followers / Following / Blocking

![Relationships View]

From the main screen, tap any relationship count:

- **Followers** — accounts that follow you
- **Following** — accounts you follow
- **Blocking** — accounts you've blocked

### What You Can Do

- **Search** — filter by handle or display name
- **Navigate** — tap any account to inspect their profile
- **Block** — swipe left or use context menu
- **Add to List** — context menu → Add to List
- **Export CSV** — tap the share icon to export the list

### Index Numbers

Each row shows an index number for easy reference.

### "New" Badge

Accounts created within the last 28 days show an orange **New** badge.

### Caching

Relationship data is cached to disk for instant loading on revisit. Pull to refresh for fresh data.

### Follower Changes (Diff)

![Follower Diff]

Access via **⋯ → Follower Diff**:

1. **First visit** — captures a baseline snapshot
2. **Subsequent visits** — shows who followed and who unfollowed since baseline
3. New followers are shown in green, unfollowed in red

---

## 7. Bulk Operations

### Bulk Profile Lookup

![Bulk Lookup]

Access via **⋯ → Bulk Lookup**:

1. Paste multiple handles, DIDs, or profile URLs (one per line or comma-separated)
2. Tap **Lookup**
3. Results show resolved profiles with avatar, name, and handle
4. Tap any result to open the full profile inspector

### Bulk Add / Remove

In any list detail view:

1. **Search** for accounts to add
2. Use the checkmark to select multiple
3. Tap **Add Selected** — all are added with progress tracking
4. For removal, select members from the list and tap **Remove Selected**

### Import Handles

1. Tap the **Import** button in the list detail view toolbar
2. Paste handles/DIDs/URLs (or import a text file)
3. Preview the classification:
   - ✅ **Ready** — resolves successfully, not already in list
   - 🔄 **Already Present** — already a member
   - ⚠️ **Duplicate** — appears multiple times in the import
   - ❌ **Unresolved** — could not be found
4. Tap **Import** to add all ready items

### Action Presets

![Action Presets]

Access via **⋯ → Action Presets**:

Save reusable action combinations:
- Block + Mute + Report
- Block + Add to Spam Watch list
- Any combination of block, mute, report, and list assignment

Create a preset, then apply it to any account in one tap.

### Rules Engine

![Rules Engine]

Access via **⋯ → Rules Engine**:

Create if-then rules that automatically evaluate against profiles:

| Trigger | Example |
|---------|---------|
| Account younger than 30 days | Flag new accounts |
| Follower count below 100 | Flag low-engagement accounts |
| Handle contains text | Flag accounts matching patterns |
| Has label | Flag accounts with specific labels |

Rules can trigger: add to list, block, mute, or report.

---

## 8. Moderation Tools

### Block All Followers

In any profile view that isn't your own:
1. Tap **Block All Followers**
2. The action is queued and processed in the background
3. Progress is shown in real-time

### Action Queue

The action queue processes background operations sequentially:

- Tap the clock icon in the toolbar to view pending actions
- Cancel or retry individual actions
- Queue persists until all operations complete

### Activity Log

![Activity Log]

Access via **⋯ → Activity Log**:

- Full history of every moderation operation
- Search by operation type, handle, or summary
- Filter by type using chip buttons
- Shows successful and failed operations

### Undo Support

After a batch operation, the last undoable operation is tracked. You can retry failed items from the batch result dialog.

---

## 9. Analytics & Reports

### Dashboard

![Dashboard](screenshots/dashboard.png)

Access via **⋯ → Dashboard**:

- **Operations by Type** — bar chart showing the distribution of moderation actions
- **Recent Activity** — the 10 most recent operations
- **Top Moderated Accounts** — accounts with the most moderation actions against them

### Trend Detection

![Trend Detection]

Access via **⋯ → Trend Detection**:

Scans your followers for:
- **New accounts** — accounts created within the last 28 days
- Flags them for review with reasons

Tap any flagged account to inspect their full profile.

### Moderation Report

![Report Generator](screenshots/report.png)

Access via **⋯ → Generate Report**:

Generates a Markdown report containing:
- Total operations, successes, and failures
- Operations breakdown by type
- Recent activity log
- Exportable via Share Sheet

Useful for weekly moderation digests or team transparency.

---

## 10. Advanced Features

### Multi-Provider Support

Rulyx supports any AT Protocol PDS (Personal Data Server):

| Provider | Entryway URL |
|----------|-------------|
| **Bluesky** | `https://bsky.social` (default) |
| **Eurosky** | `https://eurosky.social` |
| **Custom** | Any PDS URL |

Auto-detection: entering a handle like `user@eurosky.social` automatically detects the provider. You can also set it manually in the Add Account screen.

### DID Method Support

- **did:plc:** — Handle history is available via PLC directory
- **did:web:** / **did:key:** — Handle history is hidden (not supported by PLC)

### List Templates

![List Templates](screenshots/templates.png)

Pre-built list templates for common use cases:
- **Spam Watch** — track spam accounts
- **Reply Guys** — monitor aggressive commenters
- **Trusted Sources** — curate quality accounts
- **Community Core** — track engaged members
- **New Reports** — queue accounts for review
- **Emergency Block** — quick-action block list

### Cache Behavior

| Data | Cache Location | Freshness |
|------|---------------|-----------|
| Lists + Profile | `DashboardCache` (file) | Cache-first, refreshes on load |
| Followers/Following | `RelationshipCache` (file) | Cache-first, refreshes on open |
| Snapshots | UserDefaults | Persisted permanently |
| Operation Log | UserDefaults | Persisted permanently (last 25) |
| Account Data | UserDefaults + Keychain | Persisted permanently |

### Performance

- Pagination is resilient to rate limits — partial results are returned instead of failing entirely
- 300ms delay between batch operations to respect API rate limits
- Maximum 50 pages per follower/following fetch (5,000 accounts)

---

## 11. FAQ & Troubleshooting

### Why does the follower count differ from the list?

The count shown on the main screen comes from the Bluesky API (`followersCount`). The list shows actually loaded accounts. If pagination was interrupted (e.g., rate limited), the list may show fewer accounts than the total. Pull to refresh to retry.

### Why can't I see handle history?

Handle history is only available for `did:plc:` DIDs via the PLC directory. Accounts using `did:web:` or `did:key:` don't have a public handle history.

### How do I get an app password?

1. Go to [bsky.app/settings/app-passwords](https://bsky.app/settings/app-passwords)
2. Click **Add App Password**
3. Name it "Rulyx" and copy the generated password
4. Paste it into Rulyx's Add Account screen

### Data storage

| What | Where |
|------|-------|
| App passwords | iOS Keychain (encrypted) |
| Session tokens | iOS Keychain (encrypted) |
| List snapshots | UserDefaults (local) |
| Operation log | UserDefaults (local) |
| Profile notes | UserDefaults (local) |
| Cached followers | App Caches directory |
| Account metadata | UserDefaults (local) |

All data is stored locally on your device. Rulyx does not have a server.

### Can I use Rulyx with multiple accounts?

Yes. Add unlimited accounts and switch between them instantly. Each account's lists, relationships, and data are separate.

### Privacy

- Rulyx does not collect analytics or usage data
- No tracking, no ads, no telemetry
- All moderation data stays on your device
- Only communicates with Bluesky's AT Protocol servers and plc.directory
- Open source under the MIT license

---

## Need Help?

- **GitHub Issues**: [https://github.com/zopyx/bluesky-who-blocks-me-and-block-back/issues](https://github.com/zopyx/bluesky-who-blocks-me-and-block-back/issues)
- **License**: MIT — free to use, modify, and distribute

---

*Last updated: May 2026*
