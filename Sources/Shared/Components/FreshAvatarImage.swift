import SwiftUI

// MARK: - AvatarSession

/// Shared ephemeral URLSession for avatar image loading.
/// Bypasses all caches so avatars are always fresh from the server.
private enum AvatarSession {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
}

// MARK: - FreshAvatarImage

/// Loads a remote avatar image bypassing both the shared URLCache
/// and SwiftUI's internal AsyncImage cache. Uses an ephemeral
/// URLSession so each fetch is a fresh network request.
///
/// Avatars change infrequently and are small, so caching is not
/// needed. This prevents stale avatars from lingering after a
/// profile picture update on Bluesky.
struct FreshAvatarImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

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
        if loadedURL == url, uiImage != nil { return }

        do {
            let (data, response) = try await AvatarSession.session.data(from: url)
            guard (200 ..< 300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
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
