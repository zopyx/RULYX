import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published var isLocked = false
    @Published var isAuthenticating = false

    @AppStorage("appLockEnabled") var isEnabled = false {
        didSet {
            if !isEnabled {
                isLocked = false
            }
        }
    }

    @AppStorage("appLockTimeout") var timeoutMinutes: Int = 1

    private var backgroundEntryTime: Date?
    private var didEnterBackground = false

    private init() {
        if isEnabled {
            isLocked = true
        }
    }

    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var biometricLabel: String {
        switch biometricType {
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        default: "Biometrics"
        }
    }

    func appDidEnterBackground() {
        backgroundEntryTime = Date()
        didEnterBackground = true
        if isEnabled, timeoutMinutes == 0 {
            isLocked = true
        }
    }

    func appDidBecomeActive() {
        guard isEnabled else { return }
        guard didEnterBackground else {
            if isLocked { Task { await authenticate() } }
            return
        }
        didEnterBackground = false
        if timeoutMinutes > 0, let entry = backgroundEntryTime {
            let elapsed = Date().timeIntervalSince(entry)
            if elapsed >= Double(timeoutMinutes) * 60.0 {
                isLocked = true
            }
        }
        if isLocked {
            Task { await authenticate() }
        }
    }

    func authenticate() async -> Bool {
        guard isEnabled else {
            isLocked = false
            return true
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedReason = "Authenticate to access your accounts and moderation data."
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access your accounts and moderation data."
            )
            if success {
                isLocked = false
            }
            return success
        } catch {
            isLocked = true
            return false
        }
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }
}
