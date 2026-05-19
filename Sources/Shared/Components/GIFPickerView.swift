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
                } else if let errorMessage {
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
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(.horizontal, 8)
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
            .searchable(text: $searchText, prompt: "gif.search_placeholder")
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
        let key = UserDefaults.standard.string(forKey: "klipyAPIKey")
        return key?.isEmpty == false
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
