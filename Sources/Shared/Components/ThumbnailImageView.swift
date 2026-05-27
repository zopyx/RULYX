import ImageIO
import SwiftUI
import UIKit

// MARK: - ThumbnailPipeline

/// Shared pipeline for fetching and downsampling remote images.
/// Uses an `NSCache` for in-memory caching and ImageIO for efficient downsampling
/// without decoding full-resolution images.
private actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let httpClient: HTTPClient = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache.shared
        config.waitsForConnectivity = true
        return HTTPClient(session: URLSession(configuration: config))
    }()

    // MARK: - Public

    /// Fetch and downsample an image to fit within `maxPixelSize` at the given display scale.
    func image(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) async throws -> UIImage {
        let cacheKey = "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(scale))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let (data, httpResponse) = try await httpClient.data(from: url, source: "Thumbnail Image")
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let image = try downsample(data: data, maxPixelSize: maxPixelSize * scale)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Downsample image data to the target pixel size using ImageIO (avoids full decode).
    private func downsample(data: Data, maxPixelSize: CGFloat) throws -> UIImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw URLError(.cannotDecodeRawData)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize)),
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            throw URLError(.cannotDecodeContentData)
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - ThumbnailImageView

/// An efficient thumbnail image view that downloads and down-samples remote images
/// using ImageIO, with in-memory caching. Shows a `Placeholder` view while loading.
///
/// Use this instead of plain `AsyncImage` for consistent sizing and memory efficiency.
struct ThumbnailImageView<Placeholder: View>: View {
    /// The remote image URL.
    let url: URL
    /// Maximum pixel dimension for the downsampled thumbnail.
    let maxPixelSize: CGFloat
    /// Placeholder view shown while loading.
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedTaskID: String?

    // MARK: - Body

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            await loadImage()
        }
    }

    // MARK: - Private Helpers

    /// Stable task identifier combining URL, pixel size, and display scale so the task
    /// restarts only when one of these changes.
    private var taskID: String {
        "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(displayScale))"
    }

    /// Load the thumbnail via the shared pipeline.
    private func loadImage() async {
        if loadedTaskID != taskID {
            image = nil
        }
        do {
            image = try await ThumbnailPipeline.shared.image(for: url, maxPixelSize: maxPixelSize, scale: displayScale)
            loadedTaskID = taskID
        } catch is CancellationError {
            return
        } catch {
            AppLogger.performance.debug("Thumbnail load failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
