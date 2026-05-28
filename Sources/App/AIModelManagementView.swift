import SwiftUI

/// A sheet view that displays available AI models, their download states,
/// and allows the user to download or delete models.
struct AIModelManagementView: View {
    @EnvironmentObject private var aiService: LiveAIService
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var models: [ModelBundle] = []
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section {
                ForEach(models) { model in
                    ModelRow(
                        model: model,
                        state: aiService.downloadStates[model.id] ?? .notDownloaded,
                        onDownload: { Task { await downloadModel(model) } },
                        onDelete: { Task { await deleteModel(model.id) } }
                    )
                }
            } header: {
                HStack {
                    Text(loc("ai.models.section"))
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                    }
                }
            }
        }
        .overlay {
            if models.isEmpty, !isRefreshing {
                ContentUnavailableView(
                    label: {
                        Label(loc("ai.models.empty"), systemImage: "brain")
                    },
                    description: {
                        Text(loc: "ai.models.empty_desc")
                    },
                    actions: {
                        Button(loc("ai.models.refresh")) {
                            Task { await refresh() }
                        }
                    }
                )
            }
        }
        .pageTitle(loc("ai.models.title"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarCloseButton()
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await aiService.refreshCatalog()
        models = await aiService.catalog
    }

    private func downloadModel(_ model: ModelBundle) async {
        do {
            try await aiService.download(model)
        } catch {
            // state already reflects failure via @Published downloadStates
        }
    }

    private func deleteModel(_ modelID: String) async {
        try? await aiService.delete(modelID)
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: ModelBundle
    let state: ModelDownloadState
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 4) {
                    Text(formattedSize(model.fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(roleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.description.isEmpty {
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            switch state {
            case .notDownloaded:
                Button(loc("ai.models.download"), action: onDownload)
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.medium))
                    .controlSize(.small)
            case let .downloading(progress):
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: progress, total: 1.0)
                        .frame(width: 60)
                    Text(Int(progress * 100).formatted() + "%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                Button(loc("ai.models.delete"), role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.medium))
                    .controlSize(.small)
            case let .failed(msg):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Button(loc("ai.models.retry"), action: onDownload)
                        .buttonStyle(.bordered)
                        .font(.caption.weight(.medium))
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var roleLabel: String {
        switch model.role {
        case .textClassifier: loc("ai.models.role.classifier")
        case .textGenerator: loc("ai.models.role.generator")
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        AIModelManagementView()
            .environmentObject(PreviewAIService())
            .environmentObject(LocalizationManager.shared)
    }
}
