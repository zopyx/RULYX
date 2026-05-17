# Technology Stack

**Analysis Date:** 2026-05-12

## Languages

**Primary:**
- Swift 6.0 — All application source in `Sources/`, tests in `Tests/`, and UI tests in `UITests/`
  - Enforced via `.swift-version` (line 1: `6.0`) and `project.yml` (line 10: `SWIFT_VERSION: "6.0"`)
  - Uses strict concurrency checking — `@MainActor` on all services, view models, and stores; `Sendable` on model types

**Secondary:**
- None — No Objective-C, C++, or other languages detected

## Runtime

**Environment:**
- iOS 17.0 minimum (project.yml line 5: `iOS: "17.0"`)
- macOS 14.0 minimum (project.yml line 6: `macOS: "14.0"`)
- iPadOS 17.0 (implied: device family `1,2` meaning iPhone + iPad, project.yml line 33)
- visionOS: Not targeted

**Package Manager:**
- None (no Swift Package Manager, CocoaPods, or Carthage dependencies)
- No `Package.swift`, `Podfile`, or `Cartfile` exists — all dependencies are first-party Apple frameworks only

**Lockfile:**
- Not applicable

## Frameworks

**Core:**
- **SwiftUI** — Entire UI layer (`Sources/Features/`, `Sources/Shared/Components/`)
- **Foundation** — All model types, Codable, JSONEncoder/Decoder, URLSession, ISO8601DateFormatter
- **Combine** — Used in `ModerationWorkspaceStore.swift` (line 69–76) for `objectWillChange.sink` bindings between stores
- **os** (Unified Logging) — `AppLogger` in `Sources/Shared/Support/AppLogger.swift` (line 4–11)
- **Security** (Keychain) — `KeychainService.swift` (line 2: `import Security`)
- **LocalAuthentication** — Face ID / Touch ID in `AppLockManager.swift` (line 1: `import LocalAuthentication`)
- **Network** (NWPathMonitor) — `NetworkMonitor.swift` (line 1: `import Network`)
- **WidgetKit** — `RulyxWidget.swift` (line 1: `import WidgetKit`)

**Testing:**
- **XCTest** — Unit tests in `Tests/BlueskyModerationTests/`, UI tests in `UITests/BlueskyModerationUITests/`
- No third-party testing libraries (no Quick/Nimble, no Swift Testing framework)

**Build/Dev:**
- **xcodegen** — Project generation tool, config: `project.yml` (no `.pbxproj` committed directly)
- **swiftformat** — Code formatter, config: `.swiftformat` (8 lines, 4-space indent, no semicolons)
- **swiftlint** — Linter, config: `.swiftlint.yml` (32 lines, 23 disabled rules including `line_length`, `file_length`, `force_cast`, `force_try`, `identifier_name`, `type_name`)

## Key Dependencies

**Critical (Apple SDKs — no external packages):**
- `URLSession` — All HTTP networking via `BlueskyRequestExecutor.swift` (line 70)
- `JSONEncoder` / `JSONDecoder` — Request serialization and response deserialization
- `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete` — Keychain for session tokens and app passwords
- `LAContext.evaluatePolicy` — Biometric authentication for app lock
- `NWPathMonitor` — Network connectivity monitoring
- `NSUbiquitousKeyValueStore` — iCloud account sync (no CloudKit)

**Infrastructure:**
- `WidgetKit` — iOS home screen widget `RulyxWidget` (WidgetExtension/RulyxWidget.swift)
- `UserDefaults` — Local persistence for accounts, preferences, audit logs, and widget data
- `FileManager` (caches directory) — `DashboardCache.swift` and `RelationshipCache.swift` for JSON file caching

## Configuration

**Environment:**
- `.env` file present — contains environment configuration (do NOT read contents)
- `project.yml` — Single source of truth for Xcode project settings (62 lines, targets: app, unit tests, UI tests)
- No `xcconfig` files detected

**Build:**
- `xcodegen generate` — Generates `BlueskyModeration.xcodeproj`
- Build command: `xcodebuild -project BlueskyModeration.xcodeproj -scheme BlueskyModeration -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

**Code Quality:**
- `.swiftformat` — Auto-format with `swiftformat Sources Tests`
- `.swiftlint.yml` — Lint check with `swiftlint`

## Platform Requirements

**Development:**
- macOS with Xcode 15+ (requires iOS 17.0 SDK)
- xcodegen installed (`brew install xcodegen`)
- swiftformat and swiftlint installed

**Production:**
- iOS 17.0+, iPadOS 17.0+, macOS 14.0+
- iCloud account (optional, for account sync via NSUbiquitousKeyValueStore)
- Face ID / Touch ID (optional, for app lock)

## Widget Extension

- **Target:** `RulyxWidget` in `WidgetExtension/RulyxWidget.swift`
- **Type:** `WidgetBundle` with a single `StaticConfiguration` (line 65–76)
- **Supported Families:** `.systemSmall`, `.systemMedium`
- **Refresh Policy:** Every 2 hours (line 22)
- **Data Source:** Shared `UserDefaults` key `widgetListCounts`
- **No separate widget asset catalog or plist detected** — shares app bundle identifiers

---

*Stack analysis: 2026-05-12*
