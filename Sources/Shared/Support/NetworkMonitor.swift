import Network
import SwiftUI

// MARK: - NetworkMonitor

/// Singleton that monitors network connectivity using `NWPathMonitor`.
/// Publishes `isConnected` and `connectionDescription` for SwiftUI views to react to.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    /// Whether the device has an active internet connection.
    @Published var isConnected = true
    /// Human-readable description of the current connection state.
    @Published var connectionDescription = ""

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor")

    // MARK: - Init

    private init() {
        monitor.start(queue: queue)
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionDescription = path.status == .satisfied ? "Connected" : "No Internet Connection"
            }
        }
    }

    deinit {
        monitor.cancel()
    }
}
