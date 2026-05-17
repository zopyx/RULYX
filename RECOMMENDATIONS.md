# Recommendations

Top 10 suggestions for improving Rulyx, updated to match the current repository state.

## 1. Replace the current trust delegate with a real security posture
- The request executor still contains a `PinningDelegate`, but it is not doing real certificate pinning.
- Either implement actual SPKI/certificate pinning correctly or remove the custom trust delegate and rely on standard TLS.
- Add tests that prove the chosen transport behavior.

## 2. Collapse the app onto one networking architecture
- `AppDependencies` still creates `BlueskyListService` and `BlueskyProfileService`, but the feature layer mostly talks to `LiveBlueskyClient`.
- Pick one primary abstraction and make it the real source of truth.
- Remove duplicate API mapping and request logic to reduce drift and maintenance cost.

## 3. Break up `LiveBlueskyClient`
- The client is still a large multi-role class handling sessions, lists, profiles, moderation actions, Clearsky access, and PLC history.
- Split it into smaller services or domain-specific facades behind protocols.
- Keep authentication/session recovery centralized while moving feature behavior out.

## 4. Finish dependency cleanup in the app root
- The iOS app root is leaner now, which is good.
- The next step is removing dependency objects that are still constructed but not injected or not needed by the active composition model.
- This will make app startup wiring clearer and reduce architectural ambiguity.

## 5. Standardize localization and eliminate hard-coded English UI copy
- The app has broad localization support, but many visible strings and accessibility labels are still hard-coded in English.
- Move remaining strings into one localization system consistently.
- Review new language bundles for untranslated fallback content before release.

## 6. Persist workspace behavior consistently
- `lastProfileQuery` persists, but `selectedTab` still does not.
- Audit all user-facing state for consistency between “session-only” and “remembered” behavior.
- Make persistence rules explicit so the UX feels intentional.

## 7. Reduce view complexity in the largest screens
- `ListsView`, `ListDetailView`, `RelationshipsView`, `ProfileInspectorView`, and `BlueskyProfileView` are still large and state-heavy.
- Continue extracting presentation logic, sheet handling, and async workflow orchestration into smaller units.
- This will lower regression risk in the highest-change screens.

## 8. Strengthen bulk-action performance and control
- The queue and batch flow are usable, but execution is still conservative and mostly serial.
- Add bounded concurrency, better cancellation semantics, and more precise retry handling for large moderation jobs.
- Preserve safety, but improve throughput for real operator workloads.

## 9. Expand end-to-end test coverage around critical workflows
- Unit coverage is good, and UI smoke coverage has improved.
- Add UI tests for account creation, account switching, list loading, member add/remove flows, import flows, and profile moderation actions.
- Focus on the paths most likely to break from UI or state-management changes.

## 10. Clarify which “advanced” features are core workflows
- Presets, rules, notes, reports, snapshots, and background queues all exist, but not all feel equally integrated into the main user journey.
- Decide which of these are first-class product features and deepen those workflows.
- Hide, defer, or simplify capabilities that remain peripheral to the core moderation experience.
