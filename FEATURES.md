# Rulyx — Feature Overview

Rulyx is a native iOS/iPadOS moderation toolkit for Bluesky, designed for community moderators and power users who manage multiple accounts, lists, and curation workflows.

---

## Authentication & Accounts

- **Add accounts** — handle + app password via legacy `createSession`, or **OAuth browser sign-in** with PKCE + DPoP for passwordless auth
- **Two-factor authentication** — email 2FA code entry when the account requires it
- **Any PDS support** — bsky.social, Eurosky, or custom PDS entryway URLs
- **Secure storage** — app passwords and OAuth tokens stored in Keychain; DPoP private keys never exported
- **Quick switching** — floating sheet above tab bar switches accounts instantly; chat, timeline, and profile refresh automatically
- **Account labels** — tag accounts (Work, Personal, Community, Testing) with optional tint colors
- **Reorder accounts** — drag to reorder the account list in the Accounts tab
- **Preferred search account** — choose which account is used for searches (separate from active account)
- **Account import/export** — export all accounts as JSON (handle + app password); import from JSON file with validation
- **iCloud sync** — account metadata (handles, labels, PDS URLs) synced across your devices; passwords stay on-device
- **Session recovery** — legacy JWTs auto-refresh with fallback re-authentication; OAuth tokens refresh via single-use rotation

---

## Moderation Lists

- **View all lists** — grouped by Moderation Lists and Regular (curation) Lists with member counts
- **Create lists** — inline creation with name, description, and purpose type (moderation or regular)
- **Edit & delete** — update metadata or remove lists with confirmation
- **List templates** — 6 pre-built templates: Spam Watch, Reply Guys, Trusted Sources, Community Core, New Reports, Emergency Block
- **Browse members** — paginated member list with inline search and filter
- **Add members** — search Bluesky actors by handle/name, paste handles/DIDs, or import from CSV/text files with preview
- **Remove members** — swipe-to-delete or multi-select for batch removal
- **Bulk actions on members** — block, mute, unblock, or unmute selected members with confirmation and progress tracking
- **Import** — paste handles, DIDs, or profile URLs; file picker for CSV/text files; preview resolution before committing
- **Export** — download lists as CSV, JSON, XLSX, or ODS with profile stats
- **Compare lists** — side-by-side overlap view (members in both, only in A, only in B) with copy/move between lists
- **Diff lists** — transfer or copy members between lists with optional move mode
- **Snapshots** — capture point-in-time membership; compare any two snapshots to see added/removed members (up to 12 per list)
- **Growth tracking** — member count changes over time per list
- **Subscribing** — subscribe to remote moderation lists by AT URI or URL; fetch details before subscribing; "Add All" action
- **Report a list** — report a moderation list to Bluesky with reason picker and evidence text
- **Clearsky lists** — view moderation lists from the Clearsky public API
- **Internal lists** — local-only lists (not synced to Bluesky) with color coding; auto-seeded with "Hostile" (red) and "Friends" (green)

---

## Profile Inspection & Moderation

- **Full profile view** — avatar, display name, handle, description, follower/following/post/media stats
- **Relationship badges** — at-a-glance status: follows you, blocks you, you follow, you block, blocking by list
- **Blocking lists panel** — shows which moderation lists are blocking the profile
- **Moderation actions** — block, mute, report, or add to any of your lists directly from the profile
- **Block all followers** — queue-based execution with progress tracking and failure reporting
- **Block back** — detect accounts that block you but aren't blocked back; preview list; double-confirm; batch execute with progress
- **Post browser** — browse a user's posts with paginated feed and thread view
- **Media browser** — view and batch-download images/videos with created-at filenames
- **Handle history** — PLC audit log showing past handle changes (for `did:plc:` accounts)
- **Account info** — join date, labels, DID with copy button
- **Profile notes** — add/edit/view private notes about any profile
- **Export posts** — download a user's posts as CSV or JSON
- **Direct message** — start a chat from the profile (when both parties can message)
- **Apply presets** — run action presets directly from profile view
- **List membership** — view and toggle membership on all your moderation and regular lists
- **Subscribed lists viewer** — see which remote moderation lists the profile is on
- **Open in Bluesky** — quick link to bsky.app; Open in New Window on iPad

---

## Profile Search & Bulk Lookup

- **Profile inspector** — search any handle or DID and view full profile details including list memberships
- **Bulk lookup** — paste multiple handles/DIDs at once, resolve all, view results in a list
- **Saved searches** — bookmark frequently inspected profiles
- **Recent searches** — automatically tracked for quick revisit

---

## Relationship Browsing

- **Followers** — paginated list with search/filter by handle or name; navigate to profile
- **Following** — paginated list of accounts you follow
- **Blocking** — accounts you block (via Clearsky)
- **Blocked by** — accounts that block you (via Clearsky)
- **Not blocked back** — accounts that block you but you haven't blocked yet
- **Navigate to profile** — tap any actor entry for full inspection
- **Export** — download any relationship list as CSV, JSON, XLSX, or ODS

---

## Timeline & Posts

- **Following feed** — standard timeline of posts from accounts you follow
- **Custom feeds** — subscribe to any AT Protocol feed by URI; remembers last 5 feeds
- **Post interactions** — like, repost, reply, quote, or delete posts
- **Compose** — create new posts with text formatting (bold, italic, strikethrough), images, GIFs, and video attachments
- **Image resize** — auto-scales oversized images (4000×4000px / 2MB limit) before upload
- **Reply controls** — restrict replies to Everyone, Nobody, Following, Mentioned, or a Custom List
- **Allow quoting toggle** — control whether your post can be quoted
- **GIF picker** — search and select GIFs via Klipy API
- **AI text improvement** — improve post text with on-device AI
- **Thread view** — see full post thread context with blocked/not-found handling
- **Media viewer** — full-screen image carousel and HLS video player
- **Likes list** — see who liked a post
- **Muted words** — filter posts containing muted words from your timeline
- **New post detection** — URI-based tracking with unread badge
- **Block all likers** — block every account that liked a post (confirmation + progress)
- **Add all likers to list** — add all accounts that liked a post to one of your lists
- **Report post** — submit a moderation report against a specific post
- **Mute/block user** — directly from post context menu
- **Translate post** — in-app post translation
- **Share post** — system share sheet
- **Copy post** — copy post text to clipboard
- **Edit post** — delete and recreate post with updated content
- **AI classification** — run on-device AI models to classify post content
- **Manage own posts** — browse all your posts with search, date filters, and range presets; single/bulk delete with confirmation; nuclear delete-all with 3-level confirmation

---

## Custom Search & Mentions

- **Custom search** — full-text post search across Bluesky with Top / Newest / Users tabs
- **Mentions search** — search posts that @-mention your handle
- **Direct replies** — scan your posts to find direct replies with progress tracking
- **Recent searches** — automatically tracked for quick revisit
- **Post interactions** — like, reply, repost, block likers, add likers to list from search results

---

## Chat & Direct Messages

- **Conversation list** — sorted by most recent message; search conversations by handle/name
- **Group chat** — create and manage group conversations with add/remove members, lock/unlock
- **Message sending** — send text messages with optimistic inline delivery (pending → sent/failed states)
- **Message reactions** — like and reply to individual messages
- **Mute/unmute** — per-conversation mute with local and server sync
- **Delete messages** — delete sent messages
- **Paginated loading** — "Load older messages" for deep conversation history
- **System events** — displays system messages (added, removed, joined, left, locked, unlocked, group renamed)
- **Polling** — automatic 3-second poll for new messages; manual reload
- **Account switch** — conversations reload cleanly when switching accounts; stale in-flight responses discarded

---

## Notifications

- **Full notification feed** — paginated list of all notifications
- **7 notification types** — like, repost, follow, reply, quote, mention, starter-pack-joined
- **Tap to navigate** — tap a notification to view the related post thread or profile
- **Mark all as read** — batch mark-read with server sync
- **Unread badge** — badge count on the Notifications tab
- **Pull-to-refresh** — manual refresh with skeleton loading

---

## Automation & Rules

- **Action presets** — save reusable action sets (Block + Mute + Report + Add to List + Duplicate) for one-tap execution from profiles or list members
- **Moderation rules** — if-then rules with conditions: account age (<30d), follower count (<100, >1000), handle contains text, has label; actions: add to list, block, mute, report
- **Action queue** — background processing with progress tracking; view, cancel, or retry pending actions
- **Batch controller** — concurrent execution (5 at a time) with automatic retry (3 attempts) and success/failure reporting

---

## Audit & Analytics

- **Operation log** — history of the 25 most recent moderation actions with type filtering
- **Dashboard** — bar chart of operations by type, recent activity, top moderated accounts
- **List membership snapshots** — automatic periodic captures (up to 12 per list); compare any two to see churn
- **Report generator** — generate plain-text moderation activity reports with system Share sheet
- **Follower diff** — track follower changes over time with baseline capture; shows new followers and unfollowed accounts with manual refresh

---

## Trend Detection

- **Follower scan** — detect recently created accounts (<4 weeks old) in your followers
- **Flagged list** — sorted by account creation date with reason labels

---

## Network Graph

- **Followers overlap** — visualize accounts that follow both selected profiles; mutual follow detection
- **More count** — "+ N more" for shared followers beyond display limit

---

## AI & On-Device

- **AI model management** — download, delete, retry on-device AI models from catalog
- **Model roles** — classifier (post classification) and generator (text improvement)
- **Post classification** — select downloaded models, classify post content, view results
- **Text improvement** — improve post text using on-device AI generation
- **Download progress** — track model download progress with error handling

---

## iPad-Specific Features

- **NavigationSplitView** — sidebar with 4 sections (Moderation, Search & Profiles, Social, System) and 15 items
- **Command palette** — Cmd+K with fuzzy search over all features
- **Keyboard shortcuts** — Cmd+L (Lists), Cmd+D (Dashboard), Cmd+F (Search), Cmd+T (Timeline), Cmd+N (Notifications), Cmd+M (DMs), Cmd+R (Relationships), Cmd+A (Accounts), and more
- **Drag & drop** — drag actors and lists between views
- **Multi-window** — standalone profile windows via context menu "Open in New Window"
- **Dashboard** — responsive LazyVGrid layout
- **Detail column** — list member viewer, profile card with tabs
- **Handoff** — handles external events for multi-window integration

---

## Security & Privacy

- **Biometric lock** — Face ID or Touch ID to unlock the app
- **Auto-lock** — configurable timeout: immediate, 1, 5, 15, or 30 minutes
- **Keychain storage** — app passwords, app-specific passwords, and OAuth tokens stored in the iOS Keychain
- **No tracking, no ads, open source** — all data stays on your device or in your Bluesky account
- **iCloud privacy consent** — explicit alert before enabling iCloud account sync
- **Certificate pinning** — SSL pinning for bsky.social connections
- **API key redaction** — Klipy API keys automatically redacted from HTTP debug logs

---

## Settings

- **Appearance** — Light, Dark, or System
- **Language** — 16 supported languages with in-app selection (not system-dependent)
- **Biometric lock** — enable/disable Face ID or Touch ID
- **Auto-lock timeout** — configure how long before the app locks
- **iCloud sync** — enable/disable account sync with privacy consent
- **AI models** — download, delete, retry on-device AI models
- **Beta features** — toggle to show/hide beta features (Timeline tab, GIF picker)
- **GIF API key** — configure Klipy API key with health check
- **Debug mode** — diagnostic tools and verbose logging
- **HTTP debug view** — live log of all HTTP requests with response status
- **Clear cache** — flush URL cache, session caches, and image cache

---

## Push Notifications

- **APNs registration** — automatic device token registration with Apple Push Notification service
- **Bluesky PDS sync** — device token synced with the PDS for remote push delivery
- **Lifecycle management** — re-registers on foreground; cleans up on account removal
- **Local fallback** — local notification when push content arrives while polling is active

---

## Infrastructure

- **Network monitoring** — real-time connectivity detection with offline banner
- **URL caching** — 50MB memory / 200MB disk cache for Bluesky API responses
- **Skeleton loading** — loading placeholders for lists, notifications, and network graph
- **Thread cache** — in-memory cache for post thread data
- **Relationship cache** — on-disk cache for follower/following data
- **HTTP debug logging** — all requests logged with source labels; API key auto-redaction
- **Clearsky heartbeat** — periodic health check; warning banner when Clearsky is unavailable; graceful degradation

---

## Onboarding

- **Splash screen** — animated app intro on launch
- **Walkthrough** — first-launch guide explaining each of the 5 core tabs
- **Splash replay** — triple-tap the logo on the Info tab to replay the intro

## Easter Eggs

- **Debug diagnostics** — quadruple-tap the logo on the Info tab to open a hidden diagnostics screen (device model, iOS version, screen dimensions, orientation, thermal state, accessibility settings, app version)
