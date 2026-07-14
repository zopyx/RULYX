import SwiftUI

// MARK: - FreshAvatarImage

/// Loads a remote avatar image using the shared `ThumbnailPipeline` which
/// provides in-memory + disk caching and ImageIO-based downsampling.
///
/// Unlike the previous ephemeral URLSession approach, avatars benefit from
/// caching across view appearances and app relaunches, with a 24-hour TTL
/// to handle profile picture updates on Bluesky.
struct FreshAvatarImage<Placeholder: View>: View {
    let url: URL?
    /// Time-to-live in seconds for the disk cache (default 24h).
    var cacheTTL: TimeInterval = 86400
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var uiImage: UIImage?
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let uiImage, loadedURL == url {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            uiImage = nil
            loadedURL = nil
            return
        }
        if loadedURL == url, uiImage != nil {
            return
        }

        do {
            // Use ThumbnailPipeline for cached + downsampled loading
            // Avatars are typically small, so maxPixelSize ~72 * 3 = 216 at 3x
            let maxPixel: CGFloat = 72
            let image = try await ThumbnailPipeline.shared.image(
                for: url,
                maxPixelSize: maxPixel,
                scale: displayScale,
                ttl: cacheTTL
            )
            uiImage = image
            loadedURL = url
        } catch {
            if !(error is CancellationError) {
                AppLogger.performance.debug(
                    "FreshAvatarImage load failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
