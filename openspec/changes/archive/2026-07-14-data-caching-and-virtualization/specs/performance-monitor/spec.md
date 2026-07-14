## ADDED Requirements

### Requirement: The system SHALL collect HTTP request metrics
The `HTTPRequestDebugStore` SHALL collect and expose: request count (total, per-session), average/median/p99 latency per endpoint, cache hit/miss rates, and individual request details (URL, status, duration, timestamp).

#### Scenario: Request recorded
- **WHEN** an HTTP request completes
- **THEN** its URL, duration, status code, and timestamp SHALL be recorded in the store

### Requirement: A floating debug overlay SHALL display real-time metrics
A floating overlay view SHALL display the collected metrics in a compact format at the top of the screen. It SHALL be activatable via a three-finger triple-tap gesture or a toggle in Settings → Debug.

#### Scenario: Activating the overlay
- **WHEN** the user performs a three-finger triple-tap anywhere in the app
- **THEN** a small floating panel SHALL appear at the top showing: request count, avg latency, cache hit ratio, slowest endpoint

#### Scenario: Deactivating the overlay
- **WHEN** the user taps the close button on the overlay
- **THEN** the overlay SHALL be dismissed

#### Scenario: Overlay detail expansion
- **WHEN** the user taps the compact overlay
- **THEN** it SHALL expand to show the last 20 requests with full details (URL, status, duration, timestamp)

### Requirement: Metrics SHALL persist across app launches
Request metrics SHALL be saved to a JSON file on disk and restored on next launch.

#### Scenario: App relaunch
- **WHEN** the user relaunches the app
- **THEN** the previous session's metrics SHALL be available in the overlay
- **THEN** a new session SHALL be started (previous metrics still visible under "Previous Session")

### Requirement: Cache performance metrics SHALL be exposed
The API response cache SHALL expose hit/miss counts and current size to the performance monitor.

#### Scenario: Cache stats in overlay
- **WHEN** the overlay is active
- **THEN** it SHALL display: cache hit count, cache miss count, cache hit ratio (%), current cache size
