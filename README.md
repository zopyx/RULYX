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
