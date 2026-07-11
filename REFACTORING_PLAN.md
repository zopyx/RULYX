# RULYX Architecture Refactoring Plan

> Target: raise architecture from 6.5/10 to 9/10 and testing from 5/10 to 9/10
> Scope: 12 weeks, solo developer ~50% allocation
> Baseline: 49,367 LOC · 222 Swift files · 510 test functions

---

## Current State

### Architecture Score: 6.5/10

| Area | Rating | Notes |
|------|--------|-------|
| Service layer | 7/10 | Clean DI via AppDependencies, good keychain handling |
| View layer | 5/10 | Business logic embedded in views, god objects |
| View model layer | 5/10 | Some VMs exist, inconsistent usage |
| Model/DTO layer | 7/10 | Codable + Sendable, but flat file structure |
| Testability | 4/10 | Views tightly coupled to concrete service types |
| Cross-cutting | 6/10 | i18n system is excellent; NotificationCenter navigation is not |

### Testing Score: 5/10

| Area | Rating | Notes |
|------|--------|-------|
| Unit tests | 7/10 | Good coverage of models, stores, DTOs |
| View model tests | 3/10 | Minimal — most logic lives in view bodies |
| UI tests | 2/10 | 14 tests, 11 assert "tab bar exists" |
| Snapshot tests | 4/10 | Screenshot tests exist but only for iPhone, only happy path |
| Integration tests | 4/10 | Live API tests exist but are fragile |
| Architecture tests | 0/10 | Nothing prevents layer violations |

### QA Score: 4/10

| Area | Rating | Notes |
|------|--------|-------|
| CI pipeline | 2/10 | `make test` fails (generic device) |
| Lint | 7/10 | SwiftFormat + SwiftLint |
| Localization validation | 3/10 | Tests exist but are all skipped |
| Accessibility | 2/10 | Labels on icons but no audit |
| Error handling | 6/10 | AppError + retry patterns, but views lack error states |

---

## God Objects and Top Coupling Hot Spots

| File | LOC | Problem |
|------|-----|---------|
| `Sources/Domain/Services/LiveBlueskyClient.swift` | 2102 | 50+ methods, conforms to 3 protocols, handles auth + lists + profiles + feeds + posts + notifications + chat + media + moderation + ClearSky. Unmockable. |
| `Sources/Features/Lists/BlueskyProfileView.swift` | 1945 | View with 30+ @State vars, inline blockBack(), fetchBlockPreview(), network calls in view body. |
| `Sources/Domain/Services/BlueskyAPIDTOs.swift` | 1477 | 40+ DTOs in one file across all domains. |
| `Sources/Features/Lists/RelationshipsView.swift` | 941 | Duplicate blockBack() from BlueskyProfileView. |
| `Sources/Domain/Services/ChatStore.swift` | 854 | Merges chat state, persistence, push registration, network calls. |

### Dependency Pattern (current — problematic)

```
AppDependencies creates concrete instances:
    let aiService = LiveAIService()
    let blueskyClient = LiveBlueskyClient(...)
    → injected as @EnvironmentObject

Views declare:
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    → Concrete type coupling. Unmockable. Requires full environment.
```

---

## Target Architecture

### Layer Separation

```
┌──────────────────────────────────────────────────────────────┐
│ PRESENTATION (SwiftUI Views)                                  │
│  · Thin — layout, data binding, user gestures                 │
│  · All views receive ViewModel via init() or @ObservedObject  │
│  · No service calls, no @EnvironmentObject for services       │
│  · @EnvironmentObject only for cross-cutting: localization,   │
│    app lock, debug store                                      │
├──────────────────────────────────────────────────────────────┤
│ VIEW MODEL LAYER                                              │
│  · @MainActor @Observable classes                             │
│  · One ViewModel per screen / complex component               │
│  · Receives protocol-typed services in init()                 │
│  · Exposes: @Published state, func actions() -> async         │
│  · Fully unit-testable without SwiftUI                        │
├──────────────────────────────────────────────────────────────┤
│ DOMAIN LAYER (Service Protocols + Services)                   │
│  · ~10 focused service protocols (one per AT Protocol area)   │
│  · Concrete implementations: constructor-injected deps        │
│  · Preview/Mock implementations for each service protocol     │
│  · Stores (ObservableObject) for persistent state             │
├──────────────────────────────────────────────────────────────┤
│ INFRASTRUCTURE                                                │
│  · Network (URLSession, request execution)                    │
│  · Keychain, UserDefaults                                     │
│  · Logging, analytics, heartbeats                             │
└──────────────────────────────────────────────────────────────┘
```

### Service Protocol Decomposition

**Current:** LiveBlueskyClient conforms to BlueskyAuthenticating, BlueskyListServicing, BlueskyProfileInspecting.

**Target:** One protocol per bounded context, each with an explicit mock implementation.

| Protocol | Methods | Mock |
|----------|---------|------|
| BlueskyAuthServicing | 5 | MockBlueskyAuthService |
| BlueskyProfileServicing | 12 | MockBlueskyProfileService |
| BlueskyListServicing | 15 | MockBlueskyListService |
| BlueskyFeedServicing | 8 | MockBlueskyFeedService |
| BlueskyPostServicing | 10 | MockBlueskyPostService |
| BlueskyModerationServicing | 8 | MockBlueskyModerationService |
| BlueskyNotificationServicing | 6 | MockBlueskyNotificationService |
| BlueskyChatServicing | 8 | MockBlueskyChatService |
| BlueskyClearSkyServicing | 5 | MockBlueskyClearSkyService |
| BlueskyMediaServicing | 4 | MockBlueskyMediaService |

Each service protocol extends Sendable. Concrete implementations delegate to BlueskyRequestExecuting. One LiveBlueskyClient orchestrates them internally (facade pattern), but views never see it. Views only see individual protocols.

### View Model Pattern (mandatory for all screens > 200 LOC)

```swift
protocol BlueskyProfileViewModelling: ObservableObject {
    var viewerState: BlueskyViewerState? { get }
    var isBlockingBack: Bool { get }
    var blockBackProgress: BlockBackProgress { get }
    func load(did: String) async
    func blockBack() async
}

class BlueskyProfileViewModel: BlueskyProfileViewModelling {
    let profileService: BlueskyProfileServicing
    let moderationService: BlueskyModerationServicing
    let clearskyService: BlueskyClearSkyServicing
    let accountStore: AccountStore

    // All state @Published. All network in async functions.
    // Testable with mock services.
}

struct BlueskyProfileView: View {
    @ObservedObject var viewModel: BlueskyProfileViewModelling
    // No @EnvironmentObject for services
}
```

### Dependency Injection (target)

```swift
// RootWire.swift (replaces AppDependencies)
struct RootWire {
    let accountStore: AccountStore
    let workspaceStore: ModerationWorkspaceStore
    let blueskyAuth: BlueskyAuthServicing
    let blueskyProfile: BlueskyProfileServicing
    let blueskyList: BlueskyListServicing
    // ... all service protocols
}

// Views receive view models, not services:
NavigationLink(value: member) {
    BlueskyProfileView(
        viewModel: BlueskyProfileViewModel(
            profileService: rootWire.blueskyProfile,
            moderationService: rootWire.blueskyModeration,
            accountStore: rootWire.accountStore
        )
    )
}
```

### Test Architecture (target pyramid)

| Layer | Share | What |
|-------|-------|------|
| L5: Live API Tests | 5% | Gated behind env vars, optional in CI. Real auth + endpoint responses. |
| L4: UI / Snapshot Tests | 15% | Full rendering with mock VMs. iPhone + iPad, states, Dynamic Type, RTL. |
| L3: Integration Tests | 20% | Store ↔ Service contracts, account routing matrix, HTTP redaction, Keychain. |
| L2: ViewModel Tests | 40% | Every @Published state transition, every async action, error handling. |
| L1: Unit Tests | 20% | Models/DTOs, pure functions, architecture conformance enforcement. |

---

## Phased Execution Plan

### Phase 1 — Foundation (Week 1–2)

**Goal:** Infrastructure that makes everything else possible.

#### 1.1 Fix the Test Runner (0.5 day)

`make test` currently fails with `Tests must be run on a concrete device`. The Makefile's `GENERIC_DESTINATION := generic/platform=iOS Simulator` does not support testing. Fix: change `test` target to use `test-sim` or auto-detect booted simulator.

Recommended Makefile change:
```makefile
SIMULATOR_DESTINATION := platform=iOS Simulator,name=iPhone 16 Pro Max
test: test-sim
```

#### 1.2 Un-Skip Localization Tests (1 day)

`LocalizationCompletenessTests.swift` has 7 `XCTSkipIf` calls. The entire file is dead. Add localization JSONs to the test bundle target membership in `project.yml` so they load at test time. Remove all `XCTSkipIf` guards. Run and fix any real failures.

#### 1.3 Create Test Bundle for Shared Helpers (0.5 day)

Extend existing `TestHelpers.swift` pattern:
- `MockServiceProtocol.swift` — protocol for mock service builders
- `XCTestCase+AssertEventually.swift` — async assertion helper
- `TestData.swift` — shared test actors, lists, DIDs

#### 1.4 Setup CI Pipeline (1 day)

GitHub Actions workflow:
- Translation validation (`make translations-validate-ci`)
- Lint (`swiftformat --lint` + `swiftlint`)
- Build + Test on simulator
- Coverage collection

---

### Phase 2 — Decouple the God Object (Week 3–4)

**Goal:** Split LiveBlueskyClient into focused service protocols. Purely additive — no view changes yet.

#### 2.1 Audit and Split Methods (2 days)

Map every method in `LiveBlueskyClient` to its domain area. Create 10 new protocol files:
```
Sources/Domain/Services/Protocols/BlueskyAuthServicing.swift
Sources/Domain/Services/Protocols/BlueskyProfileServicing.swift
Sources/Domain/Services/Protocols/BlueskyListServicing.swift
Sources/Domain/Services/Protocols/BlueskyFeedServicing.swift
Sources/Domain/Services/Protocols/BlueskyPostServicing.swift
Sources/Domain/Services/Protocols/BlueskyModerationServicing.swift
Sources/Domain/Services/Protocols/BlueskyNotificationServicing.swift
Sources/Domain/Services/Protocols/BlueskyChatServicing.swift
Sources/Domain/Services/Protocols/BlueskyClearSkyServicing.swift
Sources/Domain/Services/Protocols/BlueskyMediaServicing.swift
```

`LiveBlueskyClient` continues conforming to ALL protocols (backward compatible). No behavior change.

#### 2.2 Create Protocol Conformance Tests (2 days)

Each protocol gets an extension conformance test verifying `LiveBlueskyClient` implements every method with the correct signature. Run in CI to prevent drift.

#### 2.3 Split BlueskyAPIDTOs (1 day)

Move 40+ DTOs from one 1477-line file into endpoint-specific files:
```
Sources/Domain/Models/DTOs/ProfileDTOs.swift
Sources/Domain/Models/DTOs/ListDTOs.swift
Sources/Domain/Models/DTOs/FeedDTOs.swift
Sources/Domain/Models/DTOs/PostDTOs.swift
Sources/Domain/Models/DTOs/ChatDTOs.swift
Sources/Domain/Models/DTOs/ModerationDTOs.swift
Sources/Domain/Models/DTOs/NotificationDTOs.swift
```

#### 2.4 Create Mock Implementations (2 days)

For each service protocol, create a Mock in `Tests/TestUtilities/`:
```
Tests/TestUtilities/MockBlueskyProfileService.swift
Tests/TestUtilities/MockBlueskyListService.swift
Tests/TestUtilities/MockBlueskyFeedService.swift
...
```

Each mock stores calls for assertion and returns pre-configured results. Use the existing `MockURLProtocol` pattern.

---

### Phase 3 — Extract View Models (Week 5–7)

**Goal:** Move business logic out of views into testable view models. This is the transform that enables 90% of testing improvements.

#### 3.1 Priority Order (by risk + LOC, 5 days)

| View | LOC | ViewModel Target |
|------|-----|-----------------|
| BlueskyProfileView | 1945 | BlueskyProfileViewModel+V2 |
| RelationshipsView | 941 | RelationshipsViewModel |
| FeedTimelineView | 692 | FeedTimelineViewModel (exists, needs protocol injection) |
| ComposePostView | 863 | ComposePostViewModel |
| UserPostsView | 829 | UserPostsViewModel (exists, needs protocol injection) |
| ListDetailView | 839 | ListDetailViewModel (exists, needs de-duplication) |

#### 3.2 Extraction Method (per View)

1. Identify all `@State` vars that are not pure UI (e.g., animation)
2. Move them to a new `@Observable` class as `@Published`
3. Move all async functions (network calls, blockBack, fetch) to VM
4. View receives VM via `init()`, VM receives services via `init()`
5. Write ViewModel tests BEFORE changing the view (verify old behavior)
6. Replace `@EnvironmentObject` service refs in View with VM calls
7. Remove `@EnvironmentObject` for services, keep only cross-cutting
8. Update all navigation destinations that construct this View

#### 3.3 Duplication Removal (1 day)

Merge `blockBack()` from `BlueskyProfileView` and `RelationshipsView` into a shared `AutoBlockBackService`. The service already exists for background operations. The foreground/manual block back should use the same service.

---

### Phase 4 — Protocol-Based DI (Week 8)

**Goal:** Replace `@EnvironmentObject` with constructor injection for all service dependencies. Views receive view models, not services.

#### 4.1 Create RootWire (1 day)

Replace the 10 `@EnvironmentObject` injections in `RULYXApp.swift` with a single `RootWire` struct. Views and VMs receive what they need via `init()`, not from the global environment.

#### 4.2 Remove @EnvironmentObject for Services (1 day)

Keep `@EnvironmentObject` only for:
- `LocalizationManager` (cross-cutting, used by 80+ views)
- `AppLockManager` (cross-cutting)
- `HTTPRequestDebugStore` (debug-only)

Remove from all views that already have view models.

---

### Phase 5 — Fill the Test Gaps (Week 9–12)

#### 5.1 Account Context Routing Tests (2 days)

Test matrix: every AGENTS.md routing rule.
- Active vs. preferred search account routing
- Fallback behavior on account deletion
- Profile view: viewerAccount, dataAccount, searchAccount dispatch

#### 5.2 HTTP Redaction Tests (1 day)

- `sanitizeURL()` — URLs with/without Klipy keys, JWT tokens, edge cases
- `sanitizeErrorResponseJSON()` — JWT in JSON bodies
- Fix the NSRange reuse bug first, then test

#### 5.3 View Model Test Suite (5 days)

Every ViewModel gets:
- Successful load → published state
- Empty data → published state
- Network error → error state + retry
- Actions (block, mute, follow) → expected service calls
- Cancellation → graceful cleanup

Target: 200+ new test functions.

#### 5.4 Snapshot Tests (3 days)

Reuse existing `ScreenshotTests` infrastructure. Add tests for:
- Every screen in loading / empty / error / success states
- iPhone and iPad (`NavigationSplitView` variants)
- Dark mode, Dynamic Type, RTL Arabic

#### 5.5 UI Flow Tests (3 days)

Replace current "tab bar exists" tests with real flows:
- Open Moderation → see lists → tap list → see members → block member
- Open Search → find profile → open → inspect → block back
- Empty accounts → add account button → add flow → success
- Open Settings → enable beta → verify beta tabs appear
- iPad sidebar → select item → content column updates

#### 5.6 Architecture Enforcement Tests (1 day)

Using source analysis:
- No View file imports a Service file directly (must go through VM)
- No View file imports `BlueskyRequestExecutor`
- All service conformance files follow naming convention
- Run as part of pre-push hook

#### 5.7 Accessibility Audit + Tests (1 day)

- Programmatic check for missing accessibility labels
- Run UI tests with accessibility inspector
- Test Dynamic Type: `.accessibility(\.dynamicTypeSize, .accessibility5)`

---

## Timeline (12 Weeks)

```
│ W1 │ W2 │ W3 │ W4 │ W5 │ W6 │ W7 │ W8 │ W9 │W10 │W11 │W12 │
├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
│P1  │P1  │P2  │P2  │P3  │P3  │P3  │P4  │P5  │P5  │P5  │P5  │
│    │    │    │    │    │    │    │    │    │    │    │    │
│■■■■│■■■■│■■■■│■■■■│■■■■│■■■■│■■■■│■■  │■■■■│■■■■│■■■■│■■■■│
├────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┤
│                                                            │
│ Phase 1: Foundation          ■■■■ (test runner, CI, loc)  │
│ Phase 2: Decouple god object ■■■■ (protocols, mocks, DTOs)│
│ Phase 3: Extract view models ■■■■ (6 views → VMs)         │
│ Phase 4: Protocol-based DI   ■■   (RootWire, remove env)  │
│ Phase 5: Fill test gaps      ■■■■ (VM, snapshot, UI, arch)│
└────────────────────────────────────────────────────────────┘
```

---

## Score Projections

| Phase | Architecture | Testing | QA | View Models Independently Testable? |
|-------|-------------|---------|-----|-----------------------------------|
| Now | 6.5 | 5.0 | 4.0 | No — logic in view bodies |
| 1: Foundation | 6.5 | 5.5 | 5.0 | No — but tests actually run |
| 2: Decouple | 7.5 | 6.0 | 5.5 | No — but APIs are mockable |
| 3: View Models | 8.0 | 7.0 | 6.5 | YES |
| 4: Protocol DI | 8.5 | 7.5 | 7.0 | YES — VMs receive mock services |
| 5: Test Gaps | 9.0 | 9.0 | 8.5 | YES — plus snapshot, UI, arch tests |

**The inflection point is Phase 3.** Before it, tests are written against SwiftUI views (slow, fragile). After it, tests target `@Observable` view models (fast, deterministic). Effort-per-test drops 5x.

---
