# Release History

## 1.0.7 (Build 61) — 2026-05-31

- **Email 2FA support**: Accounts with Bluesky email two-factor authentication can now be added. When 2FA is required, a verification code input is shown, and the session is completed after submitting the code sent via email.
- **Chat account switching**: In-flight requests after an account switch are now properly discarded, preventing stale data from appearing. Sessions are validated against the owning account's DID before use, and a status banner shows when the chat is reloading.
- **Post display**: Cited post text is larger, action bar colors are lighter in dark mode, and single landscape images no longer have excess empty space.
- **Chat list polish**: Only the conversation partner is shown (no duplicate names), with proper bottom spacing above the tab bar.
- **Account switcher**: Solid background for the switcher sheet.

## 1.0.6 (Build 60) — 2026-05-XX

- **Optimistic chat messages**: Messages now appear immediately as pending, then update to sent or failed. Failed messages can be retried with a single tap. Reaction display for sends/retries is more reliable.
- **Chat reliability**: Reduced polling interval to 3s, fixed duplicate messages from optimistic sends racing with poll, and prevented full conversation reloads on message-only push sync.
- **Conversation loading**: All pages of conversations are now fetched (no pagination gaps), and the list reloads when a message arrives for an unknown conversation. Duplicate `loadConvos` calls on account switch are eliminated.
- **Account switcher (tab bar)**: Replaced the Menu-based switcher with a sheet-based floating switcher above the tab bar, accessible from every tab. Removed the inline per-tab toolbar switcher.
- **Notifications**: Tapping a related post now opens the thread view. Notifications are no longer gated behind beta features.

## 1.0.5 (Build 59) — 2026-05-XX

- **iPadOS support**: Native iPad sidebar with NavigationSplitView, list browser, profile inspector, command palette (Cmd+K), drag-and-drop, and keyboard shortcuts.
- **Push notifications**: Production push notifications enabled with local notification fallback for chat messages.
- **Direct Messages**: DM button hidden when the other account blocks you or when you both follow each other (mutual follow restriction).
- **Timeline**: Blue FAB-style compose button added matching the Chat tab design.
- **Thread view**: Handles blocked and not-found posts from the API with improved dark mode contrast.
- **GIF support**: GIF picker is now gated behind beta features toggle.
- **i18n**: Unified page titles across all screens, improved translation consistency, iPad-specific localization keys added.

## 1.0.4 — 2026-05-XX

- **Post management**: Browse, search, filter, and delete your own posts from the profile view. Includes swipe-to-delete, bulk select, and a nuclear "delete all" option with confirmation steps.
- **Screenshot system**: Automated screenshot capture with `.env` credential loading, beta feature gating, and Fastlane integration for App Store screenshots.
- **Code documentation**: Comprehensive documentation added across the entire codebase.

## 1.0.3 — 2026-05-XX

- Initial public release.
