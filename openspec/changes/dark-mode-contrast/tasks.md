## 1. Bulk replace .tertiary with .secondary in user-facing views

- [ ] 1.1 `BlueskyProfileView.swift`: Replace all ~12 `.foregroundStyle(.tertiary)` with `.foregroundStyle(.secondary)` — section labels, stats, metadata
- [ ] 1.2 `CustomSearchView.swift`: Replace ~5 instances — search result handles, descriptions
- [ ] 1.3 `MentionsSearchView.swift`: Replace ~2 instances — search result handles
- [ ] 1.4 `RelationshipsView.swift`: Replace ~3 instances — count badges, date labels
- [ ] 1.5 `AccountTabView.swift`: Replace ~1 instance — account detail label
- [ ] 1.6 `ComposePostView.swift`: Replace ~3 instances — character count, placeholders
- [ ] 1.7 `Profile/UserPostsView.swift`: Replace ~7 instances — post timestamps, metadata
- [ ] 1.8 `Profile/ManagePostsView.swift`: Replace ~5 instances — post metadata
- [ ] 1.9 `Profile/MediaBrowserView.swift`: Replace ~3 instances — date labels, counters
- [ ] 1.10 `FeedTimelineView.swift`, `ListTimelineView.swift`: Replace ~2 instances — timeline end markers
- [ ] 1.11 `AIModelManagementView.swift`, `HTTPRequestDebugView.swift`, `PerformanceMonitorOverlay.swift`: Replace ~4 instances
- [ ] 1.12 `RootView.swift`, `FeedPickerView.swift`: Replace ~2 instances — onboarding text, feed descriptions
- [ ] 1.13 `InfoView.swift`: Review ~10 uses — keep .tertiary for decorative feature card text, replace for readable labels
- [ ] 1.14 `ConversationDetailView.swift`: Replace ~5 instances — system messages, timestamps, deleted messages, muted icon
- [ ] 1.15 `ConversationListView.swift`: Replace ~3 instances — muted indicator, timestamps
- [ ] 1.16 `NewConversationSheet.swift`: Replace ~1 instance — cancel icon
- [ ] 1.17 `NotificationRow.swift`: Replace ~1 instance — notification timestamp
- [ ] 1.18 `ReplyComposerView.swift`: Replace ~2 instances — placeholders, character counts
- [ ] 1.19 `AutoBlockListPickerView.swift`, `BatchOperationProgressView.swift`, `ClearskyListsView.swift`, `DirectRepliesView.swift`, `ListDetailMembersSection.swift`: Replace ~5 instances
- [ ] 1.20 `PostAuthorHeader.swift`, `PostEmbedView.swift`, `PostReplyContextView.swift`: Replace ~4 instances — handles, timestamps in post rows

## 2. Chat-specific fixes

- [ ] 2.1 `ChatMessageBubble.swift`: Replace `Color(.tertiaryLabel)` with `Color(.secondaryLabel)` for timestamps and reactions
- [ ] 2.2 `ChatMessageBubble.swift`: Bump outgoing opacity from 0.5 to 0.6 for timestamp readability

## 3. Verification

- [ ] 3.1 Build: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 3.2 Run `make lint` — SwiftFormat + SwiftLint pass
- [ ] 3.3 Validate OpenSpec: `openspec validate dark-mode-contrast --json`
