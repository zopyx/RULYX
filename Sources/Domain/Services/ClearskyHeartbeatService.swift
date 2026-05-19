import Foundation

@MainActor
final class ClearskyHeartbeatService: ObservableObject {
    static let shared = ClearskyHeartbeatService()

    @Published private(set) var isClearskyAvailable: Bool = true

    private var timerTask: Task<Void, Never>?

    private let heartbeatURL = "https://public.api.clearsky.services/"
    private let pingInterval: TimeInterval = 10
    private let timeout: TimeInterval = 5

    private init() {}

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

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func ping() async {
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
