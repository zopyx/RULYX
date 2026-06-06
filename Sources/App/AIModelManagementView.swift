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

                if case .downloading = state {
                    ProgressView(value: progressValue, total: 1.0)
                        .tint(.skyPrimary)
                }
            }

            Spacer()

            ModelDownloadIndicator(
                state: state,
                onDownload: onDownload,
                onDelete: onDelete
            )
        }
        .padding(.vertical, 4)
    }

    private var progressValue: Double {
        if case let .downloading(p) = state { return p }
        return 0
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
