import SwiftUI

/// Compact bulk-download status panel. It observes only download state so
/// segment-level updates do not force the media grid to redraw.
struct MediaDownloadProgressView: View {
    @ObservedObject var state: MediaDownloadProgressState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(loc: "profile.media.download_selected")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(state.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: state.fractionCompleted, total: 1)
                    .tint(.accentColor)

                HStack(spacing: 8) {
                    Text(progressDescription)
                    if let detail = state.detail, !detail.isEmpty {
                        Text(detail)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(loc("actions.cancel"))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }

    private var progressDescription: String {
        loc("common.progress.hint")
            .replacingOccurrences(of: "{title}", with: loc("profile.media.download_files"))
            .replacingOccurrences(of: "{completedCount}", with: "\(state.completedItems)")
            .replacingOccurrences(of: "{totalCount}", with: "\(state.totalItems)")
    }
}
