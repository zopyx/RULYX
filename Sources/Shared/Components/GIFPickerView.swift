import SwiftUI

struct GIFPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (GIFResult) -> Void

    @State private var searchText = ""
    @State private var results: [GIFResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoadedTrending = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @EnvironmentObject private var localizationManager: LocalizationManager
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !hasAPIKey {
                    ContentUnavailableView(
                        String(localized: "gif.missing_key_title"),
                        systemImage: "key.slash",
                        description: Text("gif.missing_key_desc")
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("gif.search_placeholder", text: $searchText)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if let errorMessage {
                        ContentUnavailableView(
                            String(localized: "list.detail.alert_title"),
                            systemImage: "exclamationmark.bubble",
                            description: Text(errorMessage)
                        )
                    } else if isLoading, results.isEmpty {
                        Spacer()
                        ProgressView("state.loading")
                        Spacer()
                    } else if results.isEmpty, !isLoading {
                        ContentUnavailableView(
                            String(localized: "gif.empty_title"),
                            systemImage: "magnifyingglass",
                            description: Text(verbatim: isSearching ? String(localized: "gif.no_results_desc") : String(localized: "gif.search_hint"))
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(results) { gif in
                                    Button {
                                        onSelect(gif)
                                        dismiss()
                                    } label: {
                                        AsyncImage(url: URL(string: gif.previewURL)) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Rectangle()
                                                .fill(.quaternary)
                                        }
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(height: 120)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .navigationTitle("gif.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("actions.close") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    results = []
                    hasLoadedTrending = false
                    return
                }
                Task {
                    await search(trimmed)
                }
            }
            .onAppear {
                if !hasLoadedTrending, !isSearching {
                    Task { await loadTrending() }
                }
            }
        }
    }

    private var hasAPIKey: Bool {
        KlipyKeychainHelper.exists()
    }

    private func search(_ query: String) async {
        isLoading = true
        errorMessage = nil
        do {
            results = try await GIFService.shared.search(query: query)
        } catch let error as GIFError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadTrending() async {
        guard !isSearching else { return }
        isLoading = true
        errorMessage = nil
        do {
            results = try await GIFService.shared.trending()
            hasLoadedTrending = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
