import Network
import SwiftUI

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published var isConnected = true
    @Published var connectionDescription = ""

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor")

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
