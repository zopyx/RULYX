## Why

A systematic audit of `foregroundStyle(.tertiary)` across the codebase found **82 usages** in active source files. In Dark Mode, `.tertiary` renders as a dark gray that provides insufficient contrast against the system background, making secondary labels, timestamps, handles, and descriptions difficult or impossible to read. The problem is systemic — it affects nearly every screen in the app.

## What Changes

- **Global audit**: Replace `.foregroundStyle(.tertiary)` with `.foregroundStyle(.secondary)` for all user-facing text that needs to be readable in dark mode. Keep `.tertiary` only for truly decorative elements (separators, placeholder shapes, disabled-state indicators).

- **Chat bubbles**: Replace `Color(.tertiaryLabel)` with `Color(.secondaryLabel)` in `ChatMessageBubble.swift` — timestamps and reactions inside message bubbles are nearly invisible in dark mode.

- **UltraThinMaterial backgrounds**: Review all uses of `.background(.ultraThinMaterial)` for readability of text placed on top of them. In dark mode, `.ultraThinMaterial` creates a very dark, translucent surface — text on top needs at least `.secondary` to be legible.

- **Opacity-based text**: Replace patterns like `Color(.label).opacity(0.7)` with `Color(.secondaryLabel)` (which is the system-defined secondary color at proper contrast). Lower opacities (0.5, 0.4) are particularly problematic in dark mode.

## Affected Areas

| Priority | File | Issue | Count |
|----------|------|-------|-------|
| 🔴 High | `BlueskyProfileView.swift` | Section labels, stats, metadata in `.tertiary` | ~12 uses |
| 🔴 High | `CustomSearchView.swift` | Search result handles, descriptions | ~5 uses |
| 🔴 High | `MentionsSearchView.swift` | Search result handles | ~2 uses |
| 🔴 High | `ConversationDetailView.swift` | System messages, timestamps, deleted msg | ~5 uses |
| 🔴 High | `ChatMessageBubble.swift` | Timestamps, reactions in chat bubbles | ~2 uses |
| 🟡 Medium | `RelationshipsView.swift` | Count badges, date labels | ~3 uses |
| 🟡 Medium | `AccountTabView.swift` | Account detail labels | ~1 use |
| 🟡 Medium | `ComposePostView.swift` | Character count, placeholders | ~3 uses |
| 🟡 Medium | `Profile/UserPostsView.swift` | Post timestamps, metadata | ~7 uses |
| 🟡 Medium | `Profile/ManagePostsView.swift` | Post metadata in `.tertiary` | ~5 uses |
| 🟡 Medium | `Profile/MediaBrowserView.swift` | Date labels, counters | ~3 uses |
| 🟢 Low | `FeedTimelineView.swift`, `ListTimelineView.swift` | Timeline end markers | ~2 uses |
| 🟢 Low | `InfoView.swift` | Feature descriptions, metadata | ~10 uses |
| 🟢 Low | `PostAuthorHeader.swift`, `InlineReplyRow.swift` | Handles, timestamps in posts | ~4 uses |

## Recommendation

Replace `.foregroundStyle(.tertiary)` with `.foregroundStyle(.secondary)` globally for all user-facing text elements. Keep `.tertiary` only for:
- Separator lines (`Divider()`)
- Placeholder shapes in skeleton loaders
- Disabled state indicators
- Non-text decorative elements

This is a mechanical search-and-replace that can be done across the entire codebase with minimal risk of visual regression in Light Mode (`.secondary` is slightly bolder than `.tertiary` in light mode but significantly more readable in dark mode).
