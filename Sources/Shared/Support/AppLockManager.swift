import LocalAuthentication
import SwiftUI

// MARK: - AppLockManager

/// Manages app-lock via Face ID / Touch ID / device passcode.
/// Locks the app on background entry (configurable timeout) and authenticates on foreground.
/// Includes lockout after 5 consecutive failed attempts (60s cooldown), persisted in Keychain.
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    /// Whether the app is currently locked.
    @Published var isLocked = false
    /// Whether an authentication attempt is in progress.
    @Published var isAuthenticating = false

    /// Master toggle stored in `UserDefaults` via `@AppStorage`.
    @AppStorage("appLockEnabled") var isEnabled = false {
        didSet {
            if !isEnabled {
                isLocked = false
            }
        }
    }

    /// Timeout in minutes before the app auto-locks after entering background.
    /// 0 = lock immediately on background.
    @AppStorage("appLockTimeout") var timeoutMinutes: Int = 1

    private var backgroundEntryTime: Date?
    private var didEnterBackground = false
    private var consecutiveFailedAttempts = 0
    private var lockoutUntil: Date?

    /// Injectable date provider for testing.
    var now: () -> Date = { Date() }

    // MARK: - Keychain Persistence (lockout state)

    private let keychain: KeychainServicing = KeychainService()
    private let lockoutService = "com.ajung.RULYX.lockout"
    private let lockoutFailuresAccount = "consecutiveFailures"
    private let lockoutUntilAccount = "lockoutUntil"

    // MARK: - Init

    private init() {
        loadLockout()
        if isEnabled {
            isLocked = true
        }
    }

    // MARK: - Public

    /// The type of biometrics available on the device.
    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    /// Whether biometric authentication is available.
    var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Human-readable label for the available biometric type.
    var biometricLabel: String {
        switch biometricType {
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        default: "Biometrics"
        }
    }

    /// Record the background entry time. Locks immediately if timeout is 0.
    func appDidEnterBackground() {
        backgroundEntryTime = now()
        didEnterBackground = true
        if isEnabled, timeoutMinutes == 0 {
            isLocked = true
        }
    }

    /// On becoming active, check if the timeout has elapsed and lock if needed.
    /// If already locked, trigger authentication.
    func appDidBecomeActive() {
        guard isEnabled else { return }
        guard didEnterBackground else {
            if isLocked {
                Task { await authenticate() }
            }
            return
        }
        didEnterBackground = false
        if timeoutMinutes > 0, let entry = backgroundEntryTime {
            let elapsed = now().timeIntervalSince(entry)
            if elapsed >= Double(timeoutMinutes) * 60.0 {
                isLocked = true
            }
        }
        if isLocked {
            Task { await authenticate() }
        }
    }

    /// Authenticate using biometrics or device passcode. Returns success/failure.
    /// Implements a 60-second lockout after 5 consecutive failures (persisted in Keychain).
    func authenticate() async -> Bool {
        guard isEnabled else {
            isLocked = false
            return true
        }

        if let lockoutUntil, now() < lockoutUntil {
            return false
        }

        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedReason = String.localized("biometric.auth_reason")
        do {
            // Uses .deviceOwnerAuthentication — offers passcode fallback when biometrics fail
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String.localized("biometric.auth_reason")
            )
            if success {
                isLocked = false
                consecutiveFailedAttempts = 0
                lockoutUntil = nil
                persistLockout()
            }
            return success
        } catch {
            consecutiveFailedAttempts += 1
            if consecutiveFailedAttempts >= 5 {
                lockoutUntil = now().addingTimeInterval(60)
            }
            persistLockout()
            isLocked = true
            return false
        }
    }

    /// Manually lock the app (if lock is enabled).
    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    /// Authenticate with device passcode as fallback (used for sensitive operations).
    /// Does NOT set `isLocked`.
    func authenticateSensitive() async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedReason = String.localized("biometric.auth_reason")
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String.localized("biometric.auth_reason")
            )
        } catch {
            return false
        }
    }

    /// Authenticate with biometrics ONLY — no device-passcode fallback.
    /// Reserved for the account export, which decrypts all app passwords onto
    /// disk: a shoulder-surfed passcode must not be enough to exfiltrate them.
    /// Does NOT set `isLocked`.
    func authenticateBiometricOnly() async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedReason = String.localized("biometric.auth_reason")
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String.localized("biometric.auth_reason")
            )
        } catch {
            return false
        }
    }

    // MARK: - Keychain Persistence

    /// Persists lockout state to Keychain so it survives app termination.
    private func persistLockout() {
        try? keychain.save("\(consecutiveFailedAttempts)", service: lockoutService, account: lockoutFailuresAccount)
        if let until = lockoutUntil {
            try? keychain.save("\(until.timeIntervalSince1970)", service: lockoutService, account: lockoutUntilAccount)
        } else {
            try? keychain.delete(service: lockoutService, account: lockoutUntilAccount)
        }
    }

    /// Restores lockout state from Keychain on launch.
    private func loadLockout() {
        if let countStr = try? keychain.read(service: lockoutService, account: lockoutFailuresAccount),
           let count = Int(countStr), count > 0
        {
            consecutiveFailedAttempts = count
        }
        if let untilStr = try? keychain.read(service: lockoutService, account: lockoutUntilAccount),
           let ts = TimeInterval(untilStr)
        {
            lockoutUntil = Date(timeIntervalSince1970: ts)
            // Clear expired lockout
            if let until = lockoutUntil, now() >= until {
                lockoutUntil = nil
                consecutiveFailedAttempts = 0
                try? keychain.delete(service: lockoutService, account: lockoutFailuresAccount)
                try? keychain.delete(service: lockoutService, account: lockoutUntilAccount)
            }
        }
    }
}
