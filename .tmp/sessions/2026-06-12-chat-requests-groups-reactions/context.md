# Task Context: Chat Requests + Group Chat + Reactions

Session ID: 2026-06-12-chat-requests-groups-reactions
Created: 2026-06-12
Status: in_progress

## Current Request
Implement Bluesky Chat API features:
1. **Chat Requests** — accept, decline, list requests, delete messages for self
2. **Group Chat** — create groups, add/remove members, edit name, lock/unlock
3. **Reactions** — add/remove emoji reactions on messages

## Context Files (Standards to Follow)
- .opencode/context/core/standards/code-quality.md
- .opencode/context/core/essential-patterns.md

## Reference Files (Source Material to Look At)
- Sources/Domain/Services/ChatServicing.swift — Protocol (add new methods)
- Sources/Domain/Services/ChatService.swift — Implementation (add new endpoints)
- Sources/Domain/Services/ChatAPIDTOs.swift — DTOs (add new request/response types)
- Sources/Domain/Services/ChatStore.swift — Store (add store methods)
- Sources/Domain/Models/ChatModels.swift — Domain models
- Sources/Features/Chat/ConversationListView.swift — View (add requests inbox)
- Sources/Features/Chat/ConversationDetailView.swift — View (add group management)
- Sources/Features/Chat/NewConversationSheet.swift — View (add group creation)
- Sources/Features/Chat/ChatMessageBubble.swift — View (add reaction UI)
- Sources/Features/Chat/ChatTab.swift — Tab wrapper

## External Docs Fetched
Bluesky Chat API (`chat.bsky.*` namespace) — Lexicon schemas for:
- `chat.bsky.convo.acceptConvo` — POST { convoId }
- `chat.bsky.convo.listConvoRequests` — GET ?cursor&limit
- `chat.bsky.convo.getConvoAvailability` — GET ?members[]
- `chat.bsky.convo.deleteMessageForSelf` — POST { convoId, messageId }
- `chat.bsky.convo.addMembers` — POST { convoId, members[] }
- `chat.bsky.convo.removeMembers` — POST { convoId, members[] }
- `chat.bsky.convo.editGroup` — POST { convoId, name? }
- `chat.bsky.convo.getConvoMembers` — GET ?convoId
- `chat.bsky.convo.lockConvo` / `unlockConvo` — POST { convoId }
- `chat.bsky.convo.addReaction` — POST { convoId, messageId, value }
- `chat.bsky.convo.removeReaction` — POST { convoId, messageId, value }

## Components

### Phase 1: Chat Requests
- Protocol additions (ChatServicing)
- DTOs (ChatAPIDTOs)
- Service implementation (ChatService)
- Store methods (ChatStore)
- View updates (ConversationListView, ConversationDetailView)

### Phase 2: Group Chat
- Protocol additions (ChatServicing)
- DTOs (ChatAPIDTOs)
- Service implementation (ChatService)
- Store methods (ChatStore)
- View updates (NewConversationSheet, ConversationDetailView)

### Phase 3: Reactions
- Protocol additions (ChatServicing)
- DTOs (ChatAPIDTOs)
- Service implementation (ChatService)
- Store methods (ChatStore)
- View updates (ChatMessageBubble)

## Constraints
- Follow existing patterns (performChatRequest, atproto-proxy header, DTO-to-domain mapping)
- Use loc("key") pattern for all user-facing strings — never native String(localized:)
- Existing i18n files in Sources/Shared/Localizations/ — add new keys to all 16 JSON files
- Swift 6 strict concurrency (@MainActor where needed)
- Maintain existing architecture (Protocol → Service → Store → Views)

## Exit Criteria
- [ ] Phase 1: Chat requests UI shows, accept/decline works, messages can be deleted
- [ ] Phase 2: Groups can be created, members managed, name edited, lock/unlock works
- [ ] Phase 3: Emoji reactions can be added/removed on messages
- [ ] All i18n keys added to 16 language files
- [ ] Build passes without errors
