import SwiftUI

/// Reusable view showing a model's download state with action buttons.
/// Displays a circular progress indicator during download, a green checkmark
/// when ready, error info on failure, and a download button when not downloaded.
struct ModelDownloadIndicator: View {
    let state: ModelDownloadState
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        switch state {
        case .notDownloaded:
            Button(loc("ai.models.download"), action: onDownload)
                .buttonStyle(.bordered)
                .font(.caption.weight(.medium))
                .controlSize(.small)

        case .downloading:
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 4)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.skyPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text(Int(progress * 100).formatted() + "%")
                    .font(.caption2.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.primary)
            }

        case .ready:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.successGreen)
                    .font(.caption)
                Button(loc("ai.models.delete"), role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.medium))
                    .controlSize(.small)
            }

        case let .failed(msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(Color.errorRed)
                    .lineLimit(1)
                Button(loc("ai.models.retry"), action: onDownload)
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.medium))
                    .controlSize(.small)
            }
        }
    }

    private var progress: Double {
        if case let .downloading(p) = state {
            return max(p, 0.01)
        }
        return 0
    }
}
