import SwiftUI

struct LoadingPanel: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .appFont(.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStatePanel: View {
    let title: String
    let message: String

    init(title: String, message: String = "") {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .appFont(.heading)
            if !message.isEmpty {
                Text(message)
                    .appFont(.label)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct ErrorRetryBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.warningOrange)
                    .accessibilityHidden(true)
                Text(message)
                    .appFont(.label)
                Spacer()
            }

            Button(action: retry) {
                Label(loc("actions.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .glassBorderedButton()
            .accessibilityHint(loc("common.retry.hint"))
        }
        .padding()
        .appCardStyle(cornerRadius: 12, style: .subtle)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

struct BatchProgressCard: View {
    let title: String
    let completedCount: Int
    let totalCount: Int
    let currentHandle: String?
    let onCancel: (() -> Void)?

    init(
        title: String,
        completedCount: Int,
        totalCount: Int,
        currentHandle: String?,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentHandle = currentHandle
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).appFont(.subheading)
                Spacer()
                Text("\(completedCount)/\(totalCount)").appFont(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(completedCount), total: Double(totalCount))
            if let currentHandle {
                Text(currentHandle).appFont(.captionSmall).monospaced().foregroundStyle(.secondary)
            }
            if let onCancel {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: onCancel) {
                        Label(loc("actions.cancel"), systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(loc("actions.cancel"))
                }
            }
        }
        .padding()
        .appCardStyle(cornerRadius: 12, style: .subtle)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityHint(loc("common.progress.hint"))
    }
}

struct StatusChip: View {
    enum Style {
        case neutral, positive, warning, destructive, info
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .appFont(.captionSmall)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular.tint(tintColor), in: .rect(cornerRadius: .infinity))
                } else {
                    Color.clear.background(backgroundColor, in: Capsule())
                }
            }
    }

    private var foregroundColor: Color {
        switch style {
        case .neutral: .secondary
        case .positive: .successGreen
        case .warning: .warningOrange
        case .destructive: .errorRed
        case .info: Color.skyPrimary
        }
    }

    private var tintColor: Color {
        switch style {
        case .neutral: .secondary
        case .positive: .successGreen
        case .warning: .warningOrange
        case .destructive: .errorRed
        case .info: Color.skyPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral: Color(.systemGray6)
        case .positive: Color.successGreen.opacity(0.12)
        case .warning: Color.warningOrange.opacity(0.12)
        case .destructive: Color.errorRed.opacity(0.12)
        case .info: Color.skyPrimary.opacity(0.12)
        }
    }
}

struct HelpSection: View {
    let title: String
    let bulletPoints: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.subheading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bulletPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .appFont(.caption)
                            .foregroundStyle(Color.skyPrimary)
                            .frame(width: 16, height: 16)
                        Text(point)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .appCardStyle(cornerRadius: 12, style: .subtle)
    }
}

struct OnboardingRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(.subheading)
                Text(description).appFont(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(loc("common.status.hint"))
        .padding(.vertical, 8)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            LoadingPanel(message: "Loading members\u{2026}")
            EmptyStatePanel(title: "No members yet", message: "Search for accounts to add to this list.")
            ErrorRetryBanner(message: "Network connection failed.") {}
            BatchProgressCard(title: "Bulk Add", completedCount: 3, totalCount: 10, currentHandle: "user.bsky.social")
        }
        .padding(.vertical)
    }
}
