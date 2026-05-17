import ImageIO
import SwiftUI
import UIKit

private actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache.shared
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    func image(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) async throws -> UIImage {
        let cacheKey = "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(scale))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let image = try downsample(data: data, maxPixelSize: maxPixelSize * scale)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

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

struct ThumbnailImageView<Placeholder: View>: View {
    let url: URL
    let maxPixelSize: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedTaskID: String?

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

    private var taskID: String {
        "\(url.absoluteString)|\(Int(maxPixelSize))|\(Int(displayScale))"
    }

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
