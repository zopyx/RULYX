# Task Context: Chat Event-Driven Architecture

Session ID: 2026-06-04-chat-event-driven
Created: 2026-06-04T08:04:00Z
Status: in_progress

## Current Request
Implement a more event-driven approach for chat updates, replacing the constant 3-second polling loop with push-triggered syncs, fine-grained event mutations, and a 30-second fallback timer.

## Context Files (Standards to Follow)
- .opencode/context/core/standards/code-quality.md

## Reference Files (Source Material to Look At)
- Sources/Domain/Services/ChatStore.swift
- Sources/Domain/Services/PushNotificationCoordinator.swift
- Sources/Domain/Models/ChatModels.swift
- Sources/Domain/Services/ChatServicing.swift
- Sources/App/RULYXApp.swift
- Tests/RULYXTests/ChatStoreTests.swift

## External Docs Fetched
None needed — all Swift async/await patterns are already used in the codebase.

## Components
1. ChatLocalAction — enum of fine-grained local mutations
2. ChatStore — event-driven polling, targeted mutations, diff-based updates
3. PushNotificationCoordinator — switches from syncLog() to signalSync()

## Constraints
- Must maintain @MainActor isolation
- Must maintain the ChatServicing protocol contract
- Must preserve all existing test behavior
- Push notifications must still trigger immediate chat sync
- No WebSocket or server infrastructure changes
- Fallback polling must exist for reliability (30s max gap)

## Exit Criteria
- [ ] ChatStore uses AsyncStream-based event-driven polling instead of fixed 3s Task.sleep loop
- [ ] Reactions, deletes, reads, and mutes are applied via targeted local mutations instead of full reloads
- [ ] PushNotificationCoordinator triggers sync via signalSync() instead of syncLog()
- [ ] 30-second fallback timer ensures reliability if push notifications are missed
- [ ] Existing tests compile and pass
