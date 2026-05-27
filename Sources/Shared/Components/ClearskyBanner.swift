import SwiftUI

// MARK: - ClearskyBanner

/// A red banner shown when ClearSky data is unavailable.
/// Displays a cloud-slash icon with a localized message.
struct ClearskyBanner: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.slash")
                .font(.subheadline)
            Text(localizationManager.localized("clearsky.unavailable"))
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.red.opacity(0.12))
        .foregroundStyle(.red)
    }
}

#Preview {
    ClearskyBanner()
        .environmentObject(LocalizationManager.shared)
}
