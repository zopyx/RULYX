# Release Checklist — BlueskyModeration

## Pre-Build Verification

- [ ] `project.yml` is valid and references all new source files
- [ ] `xcodegen generate` produces a clean project with no warnings
- [ ] Build succeeds for Release configuration:
  ```bash
  xcodebuild -scheme BlueskyModeration -configuration Release \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build
  ```
- [ ] All unit tests pass:
  ```bash
  xcodebuild test -scheme BlueskyModeration \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
  ```

## Privacy & Compliance

- [ ] `PrivacyInfo.xcprivacy` is present in bundle root
- [ ] Privacy manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`
- [ ] `NSPrivacyTracking` is `false`
- [ ] No third-party analytics or tracking SDKs are linked
- [ ] App passwords are stored in Keychain (not UserDefaults)
- [ ] No PII is logged to console or persisted unencrypted

## Manual UI Regression

### Authentication Flow
- [ ] Add account with valid credentials succeeds
- [ ] Add account with invalid credentials shows error
- [ ] Switch between multiple accounts updates active context
- [ ] Remove account clears keychain entry

### Lists View
- [ ] Lists load and display correct member counts
- [ ] Pull-to-refresh updates list metadata
- [ ] List creation/deletion works

### List Detail
- [ ] Members load and paginate correctly
- [ ] Search Bluesky users returns results
- [ ] Add single actor appends to member list without full reload
- [ ] Bulk add selected search results works
- [ ] Swipe-to-remove member works
- [ ] Bulk remove selected members works with confirmation
- [ ] Member filter search filters locally
- [ ] Export CSV generates valid file
- [ ] Import handles from text works
- [ ] Import handles from file works
- [ ] Comparison with another list shows overlap/diff
- [ ] Transfer (copy/move) selected members works
- [ ] Snapshot captures and compares history
- [ ] Edit list metadata persists changes

### Profile Inspector
- [ ] Search suppresses stale results
- [ ] Profile inspection loads correctly
- [ ] Add to list / remove from list works

### Accessibility
- [ ] VoiceOver announces member selection state
- [ ] VoiceOver announces bulk progress as single element
- [ ] VoiceOver announces comparison bucket selections
- [ ] Dynamic Type scales all text correctly
- [ ] Reduce Motion respected (no custom animations)

## Performance Sanity Check

- [ ] List detail view does not trigger full member reload after single add
- [ ] Filtered members are cached (not recomputed per render)
- [ ] Export file URLs are cached (not rewritten per render)
- [ ] No `.task` spam on every visible member row

## App Store Assets

- [ ] App Icon (1024×1024) present in `Assets.xcassets`
- [ ] Screenshot set for iPhone (6.5" and 5.5" displays)
- [ ] App description and keywords finalized
- [ ] Support URL and marketing URL set

## Version Bump

- [ ] `MARKETING_VERSION` updated in `project.yml`
- [ ] `CURRENT_PROJECT_VERSION` (build number) incremented
- [ ] Git tag created: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
