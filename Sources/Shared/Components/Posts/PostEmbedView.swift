import SwiftUI

/// Renders the embed content of a post — images (up to 4 in a grid), videos (with play overlay),
/// external link cards, and Tenor GIF embeds (with inline preview play button).
struct PostEmbedView: View {
    let embed: RichEmbed
    var onTapImage: ((Int) -> Void)?
    var onPlayVideo: (() -> Void)?
    @State private var altTextToShow: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let video = embed.video {
                Button {
                    if let onPlayVideo {
                        onPlayVideo()
                    }
                } label: {
                    videoEmbedCard(video)
                }
                .buttonStyle(.plain)
            }

            if let images = embed.images, !images.isEmpty {
                imageGrid(images: images)
            }

            if let external = embed.external, let uri = external.uri, let url = URL(string: uri) {
                if external.isTenorEmbed, let gifURL = external.preferredInlineMediaURL {
                    Button {
                        openURL(url)
                    } label: {
                        tenorEmbedCard(previewURL: gifURL, external: external)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        openURL(url)
                    } label: {
                        externalEmbedCard(external)
                    }
                    .buttonStyle(.plain)
                }
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
                        ThumbnailImageView(url: item.thumb.flatMap(URL.init) ?? previewURL, maxPixelSize: 512) {
                            Rectangle().fill(Color.skyPrimary.opacity(0.08))
                        }
                        .aspectRatio(contentMode: isSingle ? .fit : .fill)
                        .frame(height: isSingle ? 300 : 130)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
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
                    }
                    .buttonStyle(.plain)
                }
            }
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
                        .foregroundStyle(.tertiary)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
