import SwiftUI

/// A sheet view that lets the user run AI classification or generation on a
/// specific feed post using any downloaded on-device model.
struct PostClassificationView: View {
    /// The feed entry whose post will be analyzed.
    let entry: RichFeedEntry
    @EnvironmentObject private var aiService: LiveAIService
    @EnvironmentObject private var localizationManager: LocalizationManager
    /// The list of available models from the service catalog.
    @State private var catalogModels: [ModelBundle] = []
    /// The set of model IDs the user has selected for classification.
    @State private var selectedModelIDs: Set<String> = []
    /// Results keyed by model ID.
    @State private var results: [String: AIResult] = [:]
    /// Whether classification is currently running.
    @State private var isRunning = false

    /// Represents the result of running a model on the post.
    enum AIResult {
        /// Classification scores from a text classifier model.
        case classification([String: Double])
        /// Generated text from a text generator model.
        case generation(String)
        /// Error message from a failed run.
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(authorDisplay)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    Text(postText)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            } header: {
                Text(loc: "post.classify.content")
            }

            if catalogModels.isEmpty {
                Section {
                    ContentUnavailableView(
                        label: {
                            Label(loc("ai.classify.no_models"), systemImage: "brain")
                        },
                        description: {
                            Text(loc: "ai.classify.no_models_desc")
                        }
                    )
                }
            } else {
                Section {
                    ForEach(catalogModels) { model in
                        let state = aiService.downloadStates[model.id] ?? .notDownloaded
                        ModelSelectionRow(
                            model: model,
                            state: state,
                            isSelected: selectedModelIDs.contains(model.id),
                            onTap: { toggleSelection(model.id) },
                            onDownload: { Task { await downloadModel(model) } },
                            onDelete: { Task { await deleteModel(model.id) } }
                        )
                    }
                } header: {
                    Text(loc: "ai.classify.select_models")
                }

                if !selectedModelIDs.isEmpty {
                    Section {
                        Button(action: runClassification) {
                            HStack {
                                Spacer()
                                if isRunning {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(loc("ai.classify.run"))
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                if !results.isEmpty {
                    Section {
                        ForEach(Array(results.keys.sorted()), id: \.self) { modelID in
                            if let model = catalogModels.first(where: { $0.id == modelID }),
                               let result = results[modelID]
                            {
                                ResultCard(
                                    modelName: model.name,
                                    result: result
                                )
                            }
                        }
                    } header: {
                        Text(loc: "ai.classify.results")
                    }
                }
            }
        }
        .pageTitle(loc("post.classify"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarCloseButton()
            }
        }
        .task {
            await loadModels()
        }
    }

    /// The display name or handle of the post author.
    private var authorDisplay: String {
        let author = entry.post.author
        return author?.displayName ?? author?.handle ?? "—"
    }

    /// The text content of the post being classified.
    private var postText: String {
        entry.post.safeRecord.text ?? ""
    }

    /// Loads the model catalog from the AI service.
    private func loadModels() async {
        try? await aiService.refreshCatalog()
        catalogModels = await aiService.catalog
    }

    /// Toggles selection of a model for classification. Only ready models
    /// can be selected.
    private func toggleSelection(_ id: String) {
        let state = aiService.downloadStates[id] ?? .notDownloaded
        guard state == .ready else { return }
        if selectedModelIDs.contains(id) {
            selectedModelIDs.remove(id)
        } else {
            selectedModelIDs.insert(id)
        }
    }

    private func downloadModel(_ model: ModelBundle) async {
        do {
            try await aiService.download(model)
        } catch {}
    }

    private func deleteModel(_ modelID: String) async {
        try? await aiService.delete(modelID)
    }

    /// Runs classification or generation on the post using all selected
    /// models sequentially, collecting results.
    private func runClassification() {
        isRunning = true
        results = [:]
        Task {
            for modelID in selectedModelIDs {
                guard let model = catalogModels.first(where: { $0.id == modelID }) else { continue }
                do {
                    switch model.role {
                    case .textClassifier:
                        let scores = try await aiService.classify(postText, using: modelID)
                        results[modelID] = .classification(scores)
                    case .textGenerator:
                        var text = ""
                        for try await token in aiService.complete(prompt: postText, using: modelID) {
                            text += token
                        }
                        results[modelID] = .generation(text)
                    }
                } catch {
                    results[modelID] = .failed(error.localizedDescription)
                }
            }
            isRunning = false
        }
    }
}

// MARK: - ModelSelectionRow

/// A row displaying a model's name, role, download state, and a selection
/// checkbox. Only models in the ``.ready`` state can be selected.
/// Models not yet downloaded show inline download/delete actions.
private struct ModelSelectionRow: View {
    let model: ModelBundle
    let state: ModelDownloadState
    let isSelected: Bool
    let onTap: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                            .font(.subheadline)

                        HStack(spacing: 4) {
                            Text(roleLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if state != .ready {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(stateLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if state == .ready {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.infoBlue)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .foregroundStyle(state == .ready ? .primary : .secondary)
            .disabled(state != .ready)

            if state != .ready || (state == .ready && isSelected) {
                ModelDownloadIndicator(
                    state: state,
                    onDownload: onDownload,
                    onDelete: onDelete
                )
            }
        }
    }

    private var roleLabel: String {
        switch model.role {
        case .textClassifier: loc("ai.models.role.classifier")
        case .textGenerator: loc("ai.models.role.generator")
        }
    }

    private var stateLabel: String {
        switch state {
        case .notDownloaded: loc("ai.models.not_downloaded_label")
        case .downloading: loc("ai.models.downloading_label")
        case .failed: loc("ai.models.failed_label")
        case .ready: ""
        }
    }
}

// MARK: - ResultCard

/// Displays the output of a single AI model run, showing classification
/// scores as progress bars, generated text, or an error message.
private struct ResultCard: View {
    let modelName: String
    let result: PostClassificationView.AIResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(modelName)
                .font(.subheadline.weight(.semibold))

            switch result {
            case let .classification(scores):
                let sorted = scores.sorted { $0.value > $1.value }
                ForEach(sorted.prefix(5), id: \.key) { label, score in
                    HStack {
                        Text(label)
                            .font(.caption)
                        Spacer()
                        Text(Int(score * 100).formatted() + "%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(score > 0.5 ? .red : .secondary)
                    }
                    ProgressView(value: score, total: 1.0)
                        .tint(score > 0.5 ? .red : .blue)
                }
            case let .generation(text):
                Text(text)
                    .font(.caption)
                    .textSelection(.enabled)
            case let .failed(msg):
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.warningOrange)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        PostClassificationView(
            entry: RichFeedEntry(
                post: RichPost(
                    uri: "at://did:plc:test/app.bsky.feed.post/1",
                    cid: "cid1",
                    author: RichAuthor(
                        did: "did:plc:test",
                        handle: "test.bsky.social",
                        displayName: "Test User",
                        avatar: nil
                    ),
                    record: RichRecord(
                        text: "This is a test post that could contain spam or harmful content.",
                        createdAt: "2024-01-01T00:00:00Z"
                    ),
                    embed: nil,
                    viewer: nil,
                    replyCount: 0,
                    repostCount: 0,
                    likeCount: 0,
                    indexedAt: "2024-01-01T00:00:00Z"
                ),
                reply: nil
            )
        )
        .environmentObject(PreviewAIService())
        .environmentObject(LocalizationManager.shared)
    }
}
