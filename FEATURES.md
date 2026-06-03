# Rulyx — Feature Overview

Rulyx is a native iOS moderation toolkit for Bluesky, designed for community moderators and power users who manage multiple accounts and curation workflows.

---

## Multi-Account Management

- **Add accounts** with handle and app password; supports any PDS (bsky.social, Eurosky, custom servers)
- **Secure storage** — app passwords and session tokens stored in Keychain
- **Quick switching** — tap any account to switch; active session refreshes automatically
- **Account labels** — tag accounts (Work, Personal, Community, Testing) for organization
- **iCloud sync** — account metadata synced across devices
- **Session recovery** — JWT auto-refresh with fallback re-authentication if the session expires

---

## Moderation Lists (Core Feature)

- **View all lists** — grouped by Moderation Lists and Regular (curation) Lists with member counts
- **Create lists** — inline creation with name, description, and purpose type
- **Edit & delete** — update metadata or remove lists with confirmation
- **List templates** — pre-built templates (Spam Watch, Reply Guys, Trusted Sources, Community Core, New Reports, Emergency Block) for quick setup
- **Browse members** — paginated member list with inline search and filter
- **Add members** — search Bluesky actors, paste handles/DIDs, or import from CSV/text files with preview before committing
- **Remove members** — swipe-to-delete or multi-select for batch removal
- **Import** — paste handles, DIDs, or profile URLs; file picker for CSV/text; preview all before committing
- **Export** — download lists as CSV, JSON, XLSX, or ODS with profile stats
- **Compare lists** — side-by-side overlap view (members in both, only in A, only in B)
- **Diff lists** — transfer or copy members between lists, with an optional move mode
- **Snapshots** — capture point-in-time membership; compare any two snapshots to see added/removed members
- **Growth tracking** — member count changes over time per list

---

## Profile Inspection & Moderation

- **Full profile view** — avatar, display name, handle, description, follower/following/post/media stats
- **Relationship badges** — at-a-glance status: follows you, blocks you, you follow, you block
- **Moderation actions** — block, mute, report, or add to any of your lists directly from the profile
- **Block all followers** — queue-based execution with progress tracking
- **Post browser** — browse a user's posts with paginated feed
- **Media browser** — view and download images/videos
- **Handle history** — PLC audit log showing past handle changes (for `did:plc:` accounts)
- **Account info** — join date, labels, DID with copy button
- **Export posts** — download a user's posts as CSV or JSON
- **Open in Bluesky** — quick link to bsky.app

---

## Profile Search & Bulk Lookup

- **Profile inspector** — search any handle or DID and view full profile details including list memberships
- **Bulk lookup** — paste multiple handles/DIDs at once, resolve all, view results in a list
- **Saved searches** — bookmark frequently inspected profiles
- **Recent searches** — automatically tracked for quick revisit

---

## Relationship Browsing

- **Followers** — paginated list with search/filter by handle or name
- **Following** — paginated list of accounts you follow
- **Blocking** — accounts you block (via Clearsky)
- **Blocked by** — accounts that block you ("who blocks me" via Clearsky)
- **Navigate to profile** — tap any actor entry for full inspection
- **Export** — download any relationship list as CSV, JSON, XLSX, or ODS

---

## Timeline (Beta)

- **Following feed** — standard timeline of posts from accounts you follow
- **Custom feeds** — subscribe to any AT Protocol feed by URI
- **Recent feeds** — remembers last 5 feeds for quick switching
- **Post interactions** — like, repost, reply, quote, or delete posts
- **Compose** — create new posts with text and optional image/video/GIF attachments
- **Thread view** — see full post thread context
- **Media viewer** — full-screen image carousel and HLS video player
- **Likes list** — see who liked a post
- **Mute words** — filter posts containing muted words from your timeline
- **New post detection** — URI-based tracking with unread badge

---

## Automation & Rules

- **Action presets** — save reusable action sets (e.g., Block + Mute + Report + Add to List) for one-tap execution
- **Moderation rules** — if-then rules with conditions (account age, follower count, handle text, labels) and actions (add to list, block, mute, report)
- **Action queue** — background processing with progress tracking; view, cancel, or retry pending actions
- **Batch controller** — concurrent execution (5 at a time) with automatic retry (3 attempts)

---

## Audit & Analytics

- **Operation log** — history of the 25 most recent moderation actions
- **Dashboard** — bar chart of operations by type, recent activity, top moderated accounts
- **Engagement analytics** — per-post metrics (likes, reposts, replies) snapshot and trend
- **List membership snapshots** — automatic periodic captures (up to 12 per list); compare to see churn
- **Report generator** — generate plain-text moderation activity reports with system Share sheet

---

## Trend Detection

- **Follower scan** — detect recently created accounts (<4 weeks old) in your followers
- **Flagged list** — sorted by account creation date with reason labels

---

## Network Graph

- **Followers overlap** — visualize which accounts share common followers

---

## Security & Privacy

- **Biometric lock** — Face ID or Touch ID to unlock the app
- **Auto-lock** — configurable timeout (immediate, 1, 5, 15, or 30 minutes)
- **No tracking, no ads, open source** — all data stays on your device or in your Bluesky account

---

## Settings

- **Appearance** — Light, Dark, or System
- **Language** — 16 supported languages
- **GIF API keys** — configure GIPHY, Tenor, or Imgur keys for GIF search
- **Beta features toggle** — show/hide the Timeline tab
- **Debug mode** — diagnostic tools
- **Clear cache** — flush URL and session caches

---

## Onboarding

- **Splash screen** — animated app intro on launch
- **Walkthrough** — first-launch guide explaining each of the 5 tabs
- **Splash replay** — triple-tap the logo to replay the intro
