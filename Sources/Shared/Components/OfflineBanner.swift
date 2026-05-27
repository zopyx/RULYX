import SwiftUI

// MARK: - OfflineBanner

/// An orange banner displayed when the device has no internet connection.
/// Shows a wifi-slash icon with a localized "offline" message, spanning full width.
struct OfflineBanner: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
            Text(loc: "offline.title")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(.orange)
    }
}
