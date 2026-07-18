## 1. Data Layer

- [ ] 1.1 Add `profileStats` state dictionary to `RelationshipsView`
- [ ] 1.2 Fetch stats via `fetchProfileStats` after following list loads
- [ ] 1.3 Add `filterNoPosts` state for no-posts filter

## 2. Filter UI

- [ ] 2.1 Add "No posts only" toggle below search field (following mode only)
- [ ] 2.2 Modify `filteredActors` to respect filterNoPosts when stats available

## 3. Stats Row

- [ ] 3.1 Add `@AppStorage("showActorStats")` toggle in toolbar menu (following mode only)
- [ ] 3.2 Render stats row in `actorRowLabel` when showActorStats is enabled

## 4. Localization

- [ ] 4.1 Add `rel.show_stats`, `rel.filter_no_posts`, `rel.stat_row` keys to `en.json`
- [ ] 4.2 Add keys to all other 15 language files

## 5. Build & Verify

- [ ] 5.1 Run `xcodegen generate` and build
- [ ] 5.2 Run swiftlint and swiftformat
