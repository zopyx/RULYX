import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var appLockManager: AppLockManager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.skyPrimary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if appLockManager.isAuthenticating {
                ProgressView()
                    .padding(.top, 8)
            } else {
                Button {
                    Task { await appLockManager.authenticate() }
                } label: {
                    Label(loc("lock_screen.unlock"), systemImage: icon)
                        .font(.headline)
                        .frame(maxWidth: 200)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var icon: String {
        switch appLockManager.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock.shield"
        }
    }

    private var title: String {
        switch appLockManager.biometricType {
        case .faceID: loc("lock_screen.face_id_title")
        case .touchID: loc("lock_screen.touch_id_title")
        default: loc("lock_screen.app_locked")
        }
    }

    private var subtitle: String {
        if appLockManager.isBiometricsAvailable {
            loc("lock_screen.biometric_subtitle").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel)
        } else {
            loc("lock_screen.biometric_unavailable")
        }
    }
}
