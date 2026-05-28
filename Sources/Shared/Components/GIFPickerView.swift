import SwiftUI

struct GIFPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager

    let onSelect: (GIFResult) -> Void

    @State private var searchText = ""
    @State private var results: [GIFResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if KlipyKeychainHelper.exists() {
                    searchBar
                    content
                } else {
                    ContentUnavailableView(
                        loc("gif.missing_key_title"),
                        systemImage: "key.slash",
                        description: Text(loc: "gif.missing_key_desc")
                    )
                }
            }
            .pageTitle(loc("gif.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
            .task(id: query) {
                await load(query: query)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(loc("gif.search_placeholder"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var content: some View {
        ZStack(alignment: .top) {
            if let errorMessage, results.isEmpty {
                errorState(errorMessage)
            } else if results.isEmpty, !isLoading {
                ContentUnavailableView(
                    loc("gif.empty_title"),
                    systemImage: "magnifyingglass",
                    description: Text(verbatim: query.isEmpty ? loc("gif.search_hint") : loc("gif.no_results_desc"))
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(results) { gif in
                            Button {
                                onSelect(gif)
                                dismiss()
                            } label: {
                                GIFTile(gif: gif)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(gif.title.isEmpty ? loc("compose.add_gif") : gif.title)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, isLoading ? 44 : 0)
                }
            }

            if isLoading {
                ProgressView(loc("state.loading"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 4)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                loc("list.detail.alert_title"),
                systemImage: "exclamationmark.bubble",
                description: Text(message)
            )
            Button(loc("actions.retry")) {
                Task { await load(query: query, debounce: false) }
            }
            .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func load(query: String, debounce: Bool = true) async {
        if debounce, !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard !Task.isCancelled else { return }

        isLoading = true
        errorMessage = nil
        do {
            let loadedResults = query.isEmpty
                ? try await GIFService.shared.trending()
                : try await GIFService.shared.search(query: query)
            guard !Task.isCancelled else { return }
            results = loadedResults
        } catch let error as GIFError {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct GIFTile: View {
    let gif: GIFResult

    var body: some View {
        AsyncImage(url: URL(string: gif.previewURL)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            case .empty:
                Rectangle()
                    .fill(.quaternary)
            @unknown default:
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(height: 120)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
