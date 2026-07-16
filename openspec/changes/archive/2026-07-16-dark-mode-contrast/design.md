## Context

Systematic grep found **82 uses** of `.foregroundStyle(.tertiary)` across non-test, non-iPad Swift files. In Dark Mode, `.tertiary` maps to a very dark gray that is nearly illegible on the system background. This affects the entire app — profile views, chat, search, lists, compose, notifications.

## Strategy

### Bulk Replace: `.foregroundStyle(.tertiary)` → `.foregroundStyle(.secondary)`

This is a mechanical find-and-replace for all user-facing text. The risk is minimal because:
- In Light Mode, `.secondary` is slightly bolder than `.tertiary` — a minor visual change, not a regression
- In Dark Mode, `.secondary` provides significantly better readability
- No layout or structural changes
- Each file can be reviewed independently

### Chat Bubble Fixes

`ChatMessageBubble.swift` uses opacity-based colors for non-outgoing messages:
```swift
.foregroundStyle(isOutgoing ? .white.opacity(0.5) : Color(.tertiaryLabel))
```
Replace with:
```swift
.foregroundStyle(isOutgoing ? .white.opacity(0.6) : Color(.secondaryLabel))
```

### Exceptions

The following usages of `.tertiary` SHALL remain unchanged:
- `InlineReplyRow.swift` — thread reply indicators (visually distinct)
- `TimelinePostRow.swift` — "+N" overflow indicator (decorative badge)
- `StatePanels.swift` — decorative empty-state icons
- Skeleton/placeholder views where `.tertiary` is used for non-text shapes
