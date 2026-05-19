# RULYX

**RULYX** is a native iOS moderation toolkit for Bluesky — built for moderators and power users. Free, open source, and privacy-first.

**Manage multiple accounts** with Keychain-secured credentials and iCloud sync. **Build moderation lists** from scratch or 6 templates, import/export members, compare lists, and track changes with snapshots. **Inspect any profile** — check relationship status, browse posts and media, block, mute, follow, or add to lists. **Understand relationships** with searchable, exportable views of followers, following, blocking, and blocked-by.

**Automate** with Action Presets (block + mute + report + add-to-list in one tap) and if-then Moderation Rules. Queue bulk operations like "block all followers" with live progress.

**Timeline & Chat** (beta) with custom feeds, GIFs, DMs, and push notifications. **Dashboard** with charts, activity reports, trend detection, follower diff, and network analysis.

No tracking, no ads, Keychain-only, SSL pinning, Face ID/Touch ID, 16 languages, widgets. iPhone only.

## Requirements

- iOS 17.0+
- iPhone only
- A Bluesky account with an app password

## Building

```bash
xcodegen generate
xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

## Tech Stack

- Swift 6 with strict concurrency
- SwiftUI with NavigationStack
- MVVM architecture with @EnvironmentObject DI
- xcodegen for project generation

## Preferred Search Account

When you use **Custom Search** or **Mentions Search** on the Lists tab, searches run through a specific Bluesky account rather than the active session account. You can set which account to use from the **Accounts** tab under *Preferred Search Account* — the search forms display the selected account's avatar and name as a static info row.

- Set globally in **Accounts tab** → *Preferred Search Account* menu
- Falls back to the active account if no preference is set
- If the preferred account is deleted, it resets to the first remaining account
- Search results and rate limits apply to the selected account, not necessarily the one you're currently logged in as
