import Foundation

// MARK: - ClearskyHeartbeatService

/// Periodically pings the ClearSky public API to determine whether the
/// service is available. Exposes an `@Published` boolean for SwiftUI views
/// to reactively show/hide ClearSky-dependent features.
@MainActor
class ClearskyHeartbeatService: ObservableObject {
    /// Shared singleton instance.
    static let shared = ClearskyHeartbeatService()

    /// Whether the ClearSky API is currently reachable.
    @Published private(set) var isClearskyAvailable: Bool = true

    /// The repeating ping task.
    private var timerTask: Task<Void, Never>?

    /// ClearSky health-check endpoint URL.
    private let heartbeatURL = "https://public.api.clearsky.services/"
    /// Interval between pings in seconds.
    private let pingInterval: TimeInterval = 10
    /// Request timeout for each ping.
    private let timeout: TimeInterval = 5

    init() {}

    /// Starts the periodic heartbeat timer.
    func start() {
        guard timerTask == nil else { return }
        let interval = pingInterval
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.ping()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Stops the periodic heartbeat timer.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Performs a single HEAD request to the ClearSky health endpoint and
    /// updates `isClearskyAvailable` based on the response status.
    func ping() async {
        guard let url = URL(string: heartbeatURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            isClearskyAvailable = (200 ..< 300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            isClearskyAvailable = false
        }
    }
}
