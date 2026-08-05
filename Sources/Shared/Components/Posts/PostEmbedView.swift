import SwiftUI

/// Renders the embed content of a post — images (up to 4 in a grid), videos (with play overlay),
/// external link cards, and Tenor GIF embeds (with inline preview play button).
struct PostEmbedView: View {
    let embed: RichEmbed
    var onTapImage: ((Int) -> Void)?
    var onPlayVideo: (() -> Void)?
    /// Leading padding applied to all embed content so it aligns with the post text.
    var contentLeadingPadding: CGFloat = 0
    @State private var altTextToShow: String?
    /// Aspect ratio (width / height) of the loaded single image, reported by `ThumbnailImageView`.
    @State private var singleImageRatio: CGFloat?
    /// Measured width of the single-image slot, used to compute its integral display height.
    @State private var singleImageWidth: CGFloat = 0
    @Environment(\.openURL) private var openURL

    /// Returns an integral display height for a single full-width image.
    ///
    /// The fallback is important while `ThumbnailImageView` transitions from its
    /// placeholder to the loaded image. Without a fixed integral height, SwiftUI can
    /// briefly measure the resizable image using its fractional aspect-fit height before
    /// the aspect-ratio callback updates state. In an inset grouped list that can trigger
    /// UIKit's recursive `_UICollectionViewFeedbackLoopDebugger` crash.
    static func integralSingleImageHeight(
        width: CGFloat,
        aspectRatio: CGFloat?,
        maxHeight: CGFloat = 300,
        fallbackHeight: CGFloat = 200
    ) -> CGFloat {
        guard let aspectRatio, aspectRatio > 0, width > 0 else {
            return fallbackHeight
        }
        return min(maxHeight, width / aspectRatio).rounded()
    }

    private var singleImageDisplayHeight: CGFloat {
        Self.integralSingleImageHeight(
            width: singleImageWidth,
            aspectRatio: singleImageRatio
        )
    }

    var body: some View {
        if let video = embed.video {
            Button {
                if let onPlayVideo {
                    onPlayVideo()
                }
            } label: {
                videoEmbedCard(video)
            }
            .buttonStyle(.plain)
            .padding(.leading, contentLeadingPadding)
        }

        if let images = embed.images, !images.isEmpty {
            imageGrid(images: images)
                .padding(.leading, contentLeadingPadding)
        }

        if let external = embed.external, let uri = external.uri, let url = URL(string: uri) {
            if external.isTenorEmbed, let gifURL = external.preferredInlineMediaURL {
                Button {
                    openURL(url)
                } label: {
                    tenorEmbedCard(previewURL: gifURL, external: external)
                }
                .buttonStyle(.plain)
                .padding(.leading, contentLeadingPadding)
            } else {
                Button {
                    openURL(url)
                } label: {
                    externalEmbedCard(external)
                }
                .buttonStyle(.plain)
                .padding(.leading, contentLeadingPadding)
            }
        }
    }

    // MARK: - Tenor / GIF Embed

    private func tenorEmbedCard(previewURL: URL, external: RichEmbedExternal) -> some View {
        ZStack(alignment: .bottomLeading) {
            ThumbnailImageView(url: previewURL, maxPixelSize: 720) {
                RoundedRectangle(cornerRadius: 12).fill(Color.skyPrimary.opacity(0.08))
            }
            .scaledToFill()
            .frame(height: 220)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                Label {
                    Text("GIF")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "play.circle.fill")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())

                if let title = external.title, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        }
        // Pin the button's tappable region to the visible card frame.
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Image Grid

    /// Up to 4 images in a flexible grid. Single images render full-width; 2+ render in 2-column layout.
    private func imageGrid(images: [RichEmbedImage]) -> some View {
        let isSingle = images.count == 1
        let cols = isSingle ? 1 : 2
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols),
            spacing: 4
        ) {
            ForEach(Array(images.prefix(4).enumerated()), id: \.offset) { index, item in
                if let previewURL = item.fullsize.flatMap(URL.init) {
                    Button {
                        onTapImage?(index)
                    } label: {
                        if isSingle {
                            singleImageContent(item: item, previewURL: previewURL)
                        } else {
                            gridImageContent(item: item, previewURL: previewURL)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Single full-width image. The displayed height is snapped to a whole point
    /// (see `snappedSingleImageHeight`) so the row height stays constant between
    /// layout passes — aspect-fit heights derived from fractional column widths
    /// oscillate and trigger UIKit's recursive-layout-loop crash.
    private func singleImageContent(item: RichEmbedImage, previewURL: URL) -> some View {
        ThumbnailImageView(
            url: item.thumb.flatMap(URL.init) ?? previewURL,
            maxPixelSize: 512,
            onLoadedAspectRatio: { ratio in
                singleImageRatio = ratio
            },
            placeholder: {
                Rectangle().fill(Color.skyPrimary.opacity(0.08))
            }
        )
        .scaledToFill()
        .frame(height: singleImageDisplayHeight)
        .frame(maxHeight: 300)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Pin the button's tappable region to the visible (clipped) frame —
        // resizable images can otherwise inflate hit-testing over the action bar.
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { singleImageWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in singleImageWidth = newWidth }
            }
        )
        .overlay(alignment: .topLeading) {
            altTextOverlay(item: item)
        }
    }

    /// 2-column grid cell with a fixed 130pt height.
    private func gridImageContent(item: RichEmbedImage, previewURL: URL) -> some View {
        ThumbnailImageView(url: item.thumb.flatMap(URL.init) ?? previewURL, maxPixelSize: 512) {
            Rectangle().fill(Color.skyPrimary.opacity(0.08))
        }
        .aspectRatio(contentMode: .fill)
        .frame(height: 130)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Pin the button's tappable region to the visible (clipped) frame —
        // resizable images can otherwise inflate hit-testing over the action bar.
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            altTextOverlay(item: item)
        }
    }

    @ViewBuilder
    private func altTextOverlay(item: RichEmbedImage) -> some View {
        if let alt = item.alt, !alt.isEmpty {
            Button {
                altTextToShow = alt
            } label: {
                Text("ALT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    // MARK: - External Link Card

    /// Standard link preview: thumbnail, title, description, host.
    private func externalEmbedCard(_ external: RichEmbedExternal) -> some View {
        HStack(spacing: 12) {
            if let thumb = external.thumb, let url = URL(string: thumb) {
                ThumbnailImageView(url: url, maxPixelSize: 512) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.skyPrimary.opacity(0.08))
                }
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                if let title = external.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if let description = external.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let host = external.uri.flatMap(URL.init)?.host, !host.isEmpty {
                    Label(host, systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.skyPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        }
        // Pin the button's tappable region to the visible card frame.
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Video Embed

    /// Video thumbnail with play button overlay. Falls back to a gradient + film icon when no thumbnail.
    private func videoEmbedCard(_ video: RichEmbedVideo) -> some View {
        ZStack {
            if let thumb = video.thumbnail, let url = URL(string: thumb) {
                ThumbnailImageView(url: url, maxPixelSize: 720) {
                    Rectangle().fill(Color.skyPrimary.opacity(0.08))
                }
                .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.skyPrimary.opacity(0.22), Color.skyPrimary.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "film.stack")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .frame(height: 200)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Pin the button's tappable region to the visible (clipped) frame.
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
