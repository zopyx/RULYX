---
phase: 4
plan: core-flow-simplification
subsystem: Lists, Profile, State management
tags:
  - refactor
  - state-management
  - loading-states
  - error-handling
  - batch-operations
  - refresh-semantics
requires: []
provides:
  - Standardized loading/empty/error state patterns across ListsView, ProfileInspectorView, BlueskyProfileView
  - Consistent .refreshable implementation across all list/profile views
  - Cancel mechanism for bulk batch operations
affects:
  - ListsView
  - ListDetailView
  - ProfileInspectorView
  - BlueskyProfileView
  - ListBatchController
  - ListDetailViewModel
  - StatePanels (BatchProgressCard, EmptyStatePanel)
tech-stack:
  added: []
  patterns:
    - Grouped @State structs for presentation/comparison/export state
    - Flag-based batch cancellation via isCancelled closure
    - EmptyStatePanel with optional message parameter
key-files:
  created:
    - Sources/Features/Lists/ListsView+Presentation.swift
    - Sources/Features/Lists/ListDetailView+State.swift
  modified:
    - Sources/Features/Lists/ListsView.swift
    - Sources/Features/Lists/ListDetailView.swift
    - Sources/Features/Lists/ListDetailView+Helpers.swift
    - Sources/Features/Lists/ListDetailViewModel.swift
    - Sources/Features/Lists/ListDetailViewModel+Bulk.swift
    - Sources/Features/Lists/ListBatchController.swift
    - Sources/Features/Profile/ProfileInspectorView.swift
    - Sources/Features/Lists/BlueskyProfileView.swift
    - Sources/Shared/Components/StatePanels.swift
decisions:
  - Used flat @State structs with computed bindings instead of ObservableObject for presentation state, avoiding unnecessary class overhead.
  - Used flag-based cancellation (isBatchCancelled) instead of stored Task references to avoid Sendable/actor isolation complexity.
  - Made EmptyStatePanel.message optional to accommodate single-title states like "No matching profiles found."
metrics:
  duration: ~10 minutes
  tasks: 6
  commits: 6
  files-created: 2
  files-modified: 9
  build: SUCCEEDED

# Phase 4 Plan: Core Flow Simplification Summary

Reduced state surface in ListsView and ListDetailView by grouping related `@State` properties into dedicated structs, standardized loading/empty/error state components across three major views, added consistent pull-to-refresh, and implemented a cancel mechanism for bulk batch operations.

## Tasks Executed

| # | Name | Type | Commit | Status |
|---|------|------|--------|--------|
| 1 | Extract ListsView sheet/presentation logic | refactor | `367b058` | ✅ |
| 2 | Standardize loading/empty/error states | refactor | `b982702` | ✅ |
| 3 | Standardize refresh semantics | feat | `66b4627` | ✅ |
| 4 | Reduce ListDetailView state surface | refactor | `5ac8dd1` | ✅ |
| 5 | Add progress feedback for bulk operations | feat | `55db095` | ✅ |
| 6 | Verify build | verify | `1d9b10a` | ✅ |

### Task 1: Extract ListsView sheet/presentation logic

Created `ListsView+Presentation.swift` with a `PresentationState` struct that encapsulates 10 previously separate `@State` properties into a single `@State private var presentationState`. Replaced all direct references and bindings.

| Area | Change | Impact |
|------|--------|--------|
| `ListsView+Presentation.swift` (NEW) | Created `PresentationState` struct with 10 boolean/kind properties | Centralizes all sheet/navigation state |
| `ListsView.swift` | Replaced 10 `@State` properties with `@State private var presentationState` | Reduces view state from 12 to 3 `@State` properties |

### Task 2: Standardize loading/empty/error states

Ensured consistent use of `LoadingPanel`, `EmptyStatePanel`, and `ErrorRetryBanner` across ListsView, ProfileInspectorView, and BlueskyProfileView.

| Area | Change | Impact |
|------|--------|--------|
| `ListsView.swift` | Replaced skeleton loading (`SkeletonCard`/`SkeletonGrid`/`SkeletonRow`) with `LoadingPanel` | Consistent loading appearance |
| `ListsView.swift` | Replaced `ContentUnavailableView` with `EmptyStatePanel` for empty account state | Consistent empty state appearance |
| `ProfileInspectorView.swift` | Replaced inline `ProgressView`+text loading with `LoadingPanel` | Standard loading component |
| `ProfileInspectorView.swift` | Replaced plain text "no results" with `EmptyStatePanel` | Standard empty component |
| `BlueskyProfileView.swift` | Replaced `SkeletonCard` with `LoadingPanel` | Consistent loading appearance |
| `StatePanels.swift` | Made `EmptyStatePanel.message` optional with conditional rendering | Supports title-only states |

### Task 3: Standardize refresh semantics

Added pull-to-refresh to ProfileInspectorView, matching ListsView and ListDetailView.

| Area | Change | Impact |
|------|--------|--------|
| `ProfileInspectorView.swift` | Added `.refreshable` modifier that re-triggers search with current query | All three views now support pull-to-refresh consistently |

### Task 4: Reduce ListDetailView state surface

Created `ListDetailView+State.swift` with three grouped state structs, reducing from 12 individual `@State` properties to 5.

| Area | Change | Impact |
|------|--------|--------|
| `ListDetailView+State.swift` (NEW) | Created `ExportState`, `ComparisonState`, `ImportState` structs | Clear organization of related state |
| `ListDetailView.swift` | Replaced 9 sheet/comparison/export `@State` with 3 grouped structs | Reduced from 13 to 5 `@State` properties total |
| `ListDetailView+Helpers.swift` | Updated computed properties to reference new struct members | Compiles correctly with grouped state |

### Task 5: Add progress feedback for bulk operations

Implemented a cancel mechanism for bulk batch operations using a flag-based approach.

| Area | Change | Impact |
|------|--------|--------|
| `StatePanels.swift` | Added optional `onCancel` closure to `BatchProgressCard` with cancel button | Users can cancel running batch operations |
| `ListBatchController.swift` | Added `isCancelled` closure parameter checked each iteration | Immediate cancellation of in-flight batches |
| `ListDetailViewModel.swift` | Added `isBatchCancelled` flag and `cancelBatch()` method | Single source of truth for batch state |
| `ListDetailViewModel+Bulk.swift` | Wired `isCancelled` closure in `performActorBatch` | All bulk operations inherit cancellation |
| `ListDetailView.swift` | Passed `onCancel: { viewModel.cancelBatch() }` to `BatchProgressCard` | Cancel button functional in UI |

## Verification

Build: **SUCCEEDED** — verified with `xcodebuild` for iOS Simulator.

## Deviations from Plan

None — all tasks executed as specified.

## Known Stubs

None detected.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All changes are UI/state refactoring within existing view and controller boundaries.

## Self-Check: PASSED

- [x] All 6 tasks executed and committed
- [x] Each task committed individually with proper format
- [x] No deviations from plan
- [x] All localization keys used are existing keys (no new i18n needed)
- [x] Build verified: SUCCEEDED
- [x] No stub patterns detected
- [x] No threat surface changes
