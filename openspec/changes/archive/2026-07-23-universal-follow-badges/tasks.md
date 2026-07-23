## 1. Data Model & Service Layer

- [ ] 1.1 Add optional `viewerState: BlueskyViewerState?` to `BlueskyActor` model
- [ ] 1.2 Map viewer state in `BlueskyProfileService.fetchFollowersPage()` — pass `viewer` from `GetFollowersResponse` DTO
- [ ] 1.3 Map viewer state in `BlueskyProfileService.fetchFollowingPage()` — pass `viewer` from `GetFollowsResponse` DTO
- [ ] 1.4 Map viewer state in `BlueskyProfileService.searchActorsPage()` — pass `viewer` from search response DTO

## 2. Shared Components

- [ ] 2.1 Create `MemberFollowBadgesView` in `Sources/Shared/Components/` — reusable pill badge rendering
- [ ] 2.2 Verify existing badge rendering in list detail views compiles with extracted component

## 3. RelationshipsView (Followers/Following/Blocking/BlockedBy)

- [ ] 3.1 Add `pendingFollowActions`/`pendingUnfollowActions` state + `effectiveViewerState()` to RelationshipsView
- [ ] 3.2 Add `toggleFollow()` method using `container.social.followActor`/`unfollowActor`
- [ ] 3.3 Add follow badges to `actorRowLabel()` using `MemberFollowBadgesView`
- [ ] 3.4 Add double-tap gesture to actor rows using the manual double-tap detection pattern
- [ ] 3.5 Handle optimistic UI: revert on API failure, clear pending on success

## 4. UserSearchSheet

- [ ] 4.1 Add `viewerState` to search result display (badges only — no double-tap, navigates to profile)
- [ ] 4.2 Replace `BlueskyActorRow(actor: actor)` with row including `MemberFollowBadgesView`

## 5. CustomSearchView (Users Tab)

- [ ] 5.1 Add follow badges to user search result rows using `MemberFollowBadgesView`
- [ ] 5.2 Consider double-tap follow (rows navigate to profile view — badges only may suffice)

## 6. ProfileInspectorView (Search Results)

- [ ] 6.1 Add follow badges to search result rows using `MemberFollowBadgesView`

## 7. ListDetailComparisonSection

- [ ] 7.1 Add follow badges to comparison bucket member rows using `MemberFollowBadgesView`

## 8. Build & Verify

- [ ] 8.1 Format code with `swiftformat`
- [ ] 8.2 Build project with `xcodebuild`
- [ ] 8.3 Run tests
