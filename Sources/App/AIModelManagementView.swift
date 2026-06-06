import SwiftUI

struct AIModelManagementView: View {
    @EnvironmentObject private var aiService: LiveAIService
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var models: [ModelBundle] = []
    @State private var isRefreshing = false
    @State private var diskUsage: UInt64 = 0

    var body: some View {
        ScrollView {
            if models.isEmpty, !isRefreshing {
                ContentUnavailableView(
                    label: { Label(loc("ai.models.empty"), systemImage: "brain") },
                    description: { Text(loc: "ai.models.empty_desc") },
                    actions: { Button(loc("ai.models.refresh")) { Task { await refresh() } } }
                )
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 12) {
                    if diskUsage > 0 {
                        storageCard
                    }
                    ForEach(models) { model in
                        ModelCard(
                            model: model,
                            state: aiService.downloadStates[model.id] ?? .notDownloaded,
                            onDownload: { Task { await downloadModel(model) } },
                            onCancel: { aiService.cancelDownload(model.id) },
                            onDelete: { Task { await deleteModel(model.id) } }
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(loc("ai.models.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var storageCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(loc("ai.models.storage")): \(formattedSize(Int64(diskUsage)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await aiService.refreshCatalog()
        models = await aiService.catalog
        diskUsage = await aiService.totalDiskUsage()
    }

    private func downloadModel(_ model: ModelBundle) async {
        do {
            try await aiService.download(model)
        } catch {}
        diskUsage = await aiService.totalDiskUsage()
    }

    private func deleteModel(_ modelID: String) async {
        try? await aiService.delete(modelID)
        diskUsage = await aiService.totalDiskUsage()
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

// MARK: - ModelCard

private struct ModelCard: View {
    let model: ModelBundle
    let state: ModelDownloadState
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: roleIcon)
                        .font(.body)
                        .foregroundStyle(roleColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 4) {
                        Text(formattedSize(model.fileSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(roleLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                stateIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !model.description.isEmpty {
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if case let .downloading(progress) = state {
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .tint(.skyPrimary)

                    Button(loc("actions.cancel"), action: onCancel)
                        .buttonStyle(.bordered)
                        .font(.caption.weight(.medium))
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .notDownloaded:
            Button(loc("ai.models.download"), action: onDownload)
                .buttonStyle(.borderedProminent)
                .font(.caption.weight(.semibold))
                .controlSize(.small)

        case let .downloading(progress):
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 3)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: max(progress, 0.01))
                    .stroke(Color.skyPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text(Int(progress * 100).formatted())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
            }

        case .ready:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Button(loc("ai.models.delete"), role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.medium))
                    .controlSize(.small)
            }

        case let .failed(msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button(loc("ai.models.retry"), action: onDownload)
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.medium))
                    .controlSize(.small)
            }
        }
    }

    private var roleIcon: String {
        switch model.role {
        case .textClassifier: "hand.raised.fill"
        case .textGenerator: "wand.and.stars"
        }
    }

    private var roleColor: Color {
        switch model.role {
        case .textClassifier: .orange
        case .textGenerator: .purple
        }
    }

    private var roleLabel: String {
        switch model.role {
        case .textClassifier: loc("ai.models.role.classifier")
        case .textGenerator: loc("ai.models.role.generator")
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        AIModelManagementView()
            .environmentObject(PreviewAIService())
            .environmentObject(LocalizationManager.shared)
    }
}
