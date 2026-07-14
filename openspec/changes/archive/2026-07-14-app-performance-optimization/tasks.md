## 1. ThumbnailPipeline Disk Cache

- [ ] 1.1 Add disk cache storage to `ThumbnailPipeline` actor — a caches-directory file store keyed by MD5 of `url|maxPixelSize|scale` with access-time tracking via `NSFileAccessDateKey`
- [ ] 1.2 Add `TTL` parameter to `ThumbnailPipeline.image(for:maxPixelSize:scale:ttl:)` — default 86400s (24h) for avatars, 259200s (72h) for thumbnails
- [ ] 1.3 Modify `ThumbnailPipeline.image(for:)` to check in-memory cache → disk cache → network fetch, writing to disk on fetch
- [ ] 1.4 Add disk cache eviction: when total on-disk size exceeds 50 MB, delete oldest-access-time files until usage drops below 40 MB
- [ ] 1.5 Add a `clearDiskCache()` method to `ThumbnailPipeline` for manual cache clearing

## 2. FreshAvatarImage Pipeline Migration

- [ ] 2.1 Modify `FreshAvatarImage.load()` to call `ThumbnailPipeline.shared.image(for: url, maxPixelSize: 72, scale: 3, ttl: 86400)` instead of its own ephemeral URLSession fetch
- [ ] 2.2 Remove unused `AvatarSession` private enum and the ephemeral URLSession configuration from `FreshAvatarImage.swift`
- [ ] 2.3 Ensure `FreshAvatarImage` passes through the display scale from environment for correct downsampling

## 3. View Model @Observable Migration

- [ ] 3.1 Migrate `BlueskyProfileViewModel` from `ObservableObject` + `@Published` to `@Observable` macro — test all published properties compile and views still bind
- [ ] 3.2 Update `BlueskyProfileView` to use `@State var viewModel = BlueskyProfileViewModel()` instead of `@StateObject` (required for `@Observable`)
- [ ] 3.3 Migrate `ListsViewModel` from `ObservableObject` + `@Published` to `@Observable` macro
- [ ] 3.4 Update `ListsView` to use `@State var viewModel = ListsViewModel()` instead of `@StateObject`

## 4. View Decomposition & Equatable Conformance

- [ ] 4.1 Add `Equatable` conformance to `BlueskyActor` model (or verify it already has stable `id`-based equality)
- [ ] 4.2 Add `.equatable()` modifier to `ForEach` in `RelationshipsView` list to skip unnecessary row re-renders
- [ ] 4.3 Decompose `BlueskyProfileView` body into named `@ViewBuilder` subview sections: profile header, moderation controls, list memberships, owned lists, subscribed lists, ClearSky lists, handle history, media stats
- [ ] 4.4 Break `RelationshipsView` body into subview groups: empty state, search bar, actor list, footer

## 5. Timeline Polling Efficiency

- [ ] 5.1 Move `FeedTimelineView.polling` lifecycle to `TimelineTab` using an `isVisible` binding: start polling when timeline is on screen, stop when tab switches away
- [ ] 5.2 Ensure iPadTimelineView also respects the visibility-gated polling pattern
- [ ] 5.3 Increase default polling interval from 8 seconds to 15 seconds in `startPolling(interval:)`
- [ ] 5.4 Add adaptive polling: after 120 seconds of no scroll/interaction, back off to 30-second interval; reset to 15s on user interaction
- [ ] 5.5 Remove the separate `.task` that calls `viewModel.startPolling` from `FeedTimelineView` body — lifecycle is now managed by the tab

## 6. List Rendering Optimization

- [ ] 6.1 Ensure `BlueskyActor` has stable `id` (currently uses `did`) — verify `ForEach` in `RelationshipsView` uses `\.element.id` not index-based identity
- [ ] 6.2 Verify `PostRowView` and its subcomponents (`PostAuthorHeader`, `PostTextContent`, `PostEmbedView`, `PostActionBar`) use `let` constants and no `@State` that causes unnecessary re-renders
- [ ] 6.3 Remove `appScrollTransition()` from `RelationshipsView` rows if it adds per-row animation overhead (evaluate, keep only if visually needed)

## 7. Build & Verify

- [ ] 7.1 Run `xcodegen generate` and verify project compiles with no errors
- [ ] 7.2 Build for iOS Simulator: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 7.3 Run `swiftformat Sources Tests` and fix any formatting drift
- [ ] 7.4 Run `swiftlint` and address any new warnings
- [ ] 7.5 Verify `openspec validate --change app-performance-optimization --json` passes
