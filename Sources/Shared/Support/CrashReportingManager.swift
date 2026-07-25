import Foundation
import MetricKit

/// Manages opt-in crash and performance diagnostics via MetricKit.
/// Toggle on/off from Settings. Zero-cost when disabled — no third-party SDK.
@MainActor
final class CrashReportingManager: NSObject, ObservableObject, @preconcurrency MXMetricManagerSubscriber {
    static let shared = CrashReportingManager()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "crashReportingEnabled")
            if isEnabled {
                MXMetricManager.shared.add(self)
            } else {
                MXMetricManager.shared.remove(self)
            }
        }
    }

    override private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "crashReportingEnabled")
        super.init()
        if isEnabled {
            MXMetricManager.shared.add(self)
        }
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_: [MXDiagnosticPayload]) {
        // Diagnostics are automatically delivered to Xcode Organizer → Crashes.
        // No action needed here — MetricKit handles upload to App Store Connect.
    }
}
