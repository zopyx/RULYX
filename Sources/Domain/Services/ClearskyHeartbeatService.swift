import Foundation

// MARK: - ClearskyHeartbeatService

/// Periodically probes the ClearSky API to determine whether the service is
/// available. Exposes an `@Published` boolean for SwiftUI views to reactively
/// show/hide ClearSky-dependent features.
///
/// The probe targets a real API route (`ClearskyEndpoints.healthProbeURL`), not
/// the site root: during the September 2026 ClearSky outage the root answered
/// `200` while every `/api/...` route returned `502` from the origin, so a root
/// probe reported "available" and the app surfaced raw gateway errors instead of
/// the ClearSky-unavailable state.
@MainActor
class ClearskyHeartbeatService: ObservableObject {
    /// Shared singleton instance.
    static let shared = ClearskyHeartbeatService()

    /// Whether the ClearSky API is currently reachable.
    @Published private(set) var isClearskyAvailable: Bool = true

    /// The repeating ping task.
    private var timerTask: Task<Void, Never>?

    /// ClearSky API route probed for liveness. `nil` means "cannot probe" → unavailable.
    private let healthProbeURL: URL?
    /// Interval between pings in seconds.
    private let pingInterval: TimeInterval = 10
    /// Request timeout for each ping.
    private let timeout: TimeInterval = 5
    /// Session used for the probe. Defaults to `URLSession.shared`.
    private let session: URLSession

    init(
        healthProbeURL: URL? = ClearskyEndpoints.healthProbeURL,
        session: URLSession = .shared
    ) {
        self.healthProbeURL = healthProbeURL
        self.session = session
    }

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

    /// Probes the ClearSky API route and updates `isClearskyAvailable`.
    ///
    /// ClearSky counts as available when the API answered with anything below
    /// `500`: the probe route returns `404` for an account without a blocklist,
    /// which is a healthy answer. Only `5xx` responses and transport failures
    /// (timeout, offline, TLS) mean "down".
    func ping() async {
        guard let url = healthProbeURL else {
            isClearskyAvailable = false
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            isClearskyAvailable = (1 ..< 500).contains(status)
        } catch {
            isClearskyAvailable = false
        }
    }
}
