import AVKit
import SwiftUI

struct MediaBrowserView: View {
    let did: String
    let handle: String

    @StateObject private var viewModel: MediaBrowserViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingFolderPicker = false
    @State private var selectedDownloadFolder: URL?
    @State private var previewItem: MediaItem?
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var downloadTask: Task<Void, Never>?

    init(did: String, handle: String) {
        self.did = did
        self.handle = handle
        _viewModel = StateObject(wrappedValue: MediaBrowserViewModel(did: did))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isDownloading {
                    if let progress = viewModel.downloadProgress {
                        VStack(spacing: 4) {
                            ProgressView(value: Double(progress.current), total: Double(progress.total))
                                .padding(.horizontal)
                            if let detail = viewModel.downloadStatusDetail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                    }
                }

                if !viewModel.items.isEmpty || viewModel.isScanning {
                    if viewModel.availableFilters.count > 1 {
                        HStack(spacing: 8) {
                            Picker(loc("media.filter_label"), selection: $viewModel.filter) {
                                ForEach(viewModel.availableFilters, id: \.self) { f in
                                    Text(filterLabel(f, count: f == .images ? viewModel.imageCount : viewModel.videoCount))
                                        .tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)

                            Spacer()

                            Text(viewModel.summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if viewModel.isScanning {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(verbatim: loc("profile.media.scanning"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                    } else {
                        HStack(spacing: 8) {
                            Text(viewModel.summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if viewModel.isScanning {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(verbatim: loc("profile.media.scanning"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                }

                if !viewModel.items.isEmpty {
                    Text(verbatim: loc("media.instruction"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }

                toolbar

                Group {
                    if viewModel.isLoading, viewModel.items.isEmpty {
                        Spacer()
                        LoadingPanel(message: loc("profile.posts.loading"))
                        Spacer()
                    } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                        if error.localizedCaseInsensitiveContains("blocked") {
                            ContentUnavailableView(
                                loc("profile.blocked.title"),
                                systemImage: "hand.raised.slash.fill",
                                description: Text(verbatim: loc("profile.blocked.media_desc"))
                            )
                        } else {
                            ContentUnavailableView(
                                loc("list.detail.alert_title"),
                                systemImage: "exclamationmark.bubble",
                                description: Text(error)
                            )
                        }
                    } else if viewModel.items.isEmpty {
                        ContentUnavailableView(
                            loc("profile.media.empty"),
                            systemImage: "photo.on.rectangle",
                            description: Text(verbatim: loc("profile.media.empty_desc"))
                        )
                    } else {
                        ScrollView {
                            let displayItems = viewModel.filteredItems
                            let loadMoreTriggerIDs = Set(displayItems.suffix(12).map(\.id))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                                ForEach(displayItems) { item in
                                    mediaThumbnail(item)
                                        .onAppear {
                                            if loadMoreTriggerIDs.contains(item.id) {
                                                Task { await loadMore() }
                                            }
                                        }
                                }
                            }
                        }
                        .refreshable {
                            await refresh()
                        }
                    }
                }
            }
            .navigationTitle(loc("profile.media.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.close")) { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingFolderPicker) {
                FolderPicker { url in
                    selectedDownloadFolder = url
                }
            }
            .fullScreenCover(item: $previewItem) { item in
                MediaPreviewView(item: item) { previewItem = nil }
            }
            .sheet(item: $viewModel.downloadSummary) { summary in
                NavigationStack {
                    List {
                        Section {
                            LabeledContent(loc("profile.media.download_total"), value: "\(summary.total)")
                            LabeledContent(loc("profile.media.download_succeeded"), value: "\(summary.succeeded)")
                            if summary.failed > 0 {
                                LabeledContent(loc("profile.media.download_failed"), value: "\(summary.failed)")
                                    .foregroundStyle(.red)
                            }
                            LabeledContent(loc("profile.media.download_folder"), value: summary.directory.lastPathComponent)
                        }
                        if !summary.errors.isEmpty {
                            Section {
                                ForEach(summary.errors, id: \.self) { error in
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            } header: {
                                Text(verbatim: loc("profile.media.download_errors"))
                            }
                        }
                    }
                    .navigationTitle(loc("profile.media.download_complete"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("actions.done")) {
                                viewModel.clearDownloadSummary()
                            }
                        }
                    }
                }
            }
            .onChange(of: viewModel.filter) { _, _ in viewModel.pruneSelection() }
            .onChange(of: selectedDownloadFolder) { _, url in
                guard let url else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                Task {
                    await performDownload(to: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
            .task {
                await loadInitial()
            }
            .onDisappear {
                initialLoadTask?.cancel()
                loadMoreTask?.cancel()
                downloadTask?.cancel()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if !viewModel.items.isEmpty {
                Button {
                    viewModel.selectAll.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.selectAll ? "checkmark.circle.fill" : "circle")
                        Text(loc("profile.media.select_all"))
                    }
                    .font(.body.weight(.medium))
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Spacer()

                if !viewModel.selectedIDs.isEmpty {
                    Text("\(viewModel.selectedIDs.count)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Button {
                    guard !viewModel.selectedIDs.isEmpty else { return }
                    isShowingFolderPicker = true
                } label: {
                    Label(loc("profile.media.download_selected"), systemImage: "arrow.down.circle")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .padding(.vertical, 6)
                }
                .disabled(viewModel.selectedIDs.isEmpty || viewModel.isDownloading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func mediaThumbnail(_ item: MediaItem) -> some View {
        let isSelected = viewModel.selectedIDs.contains(item.id)
        let imageURL = URL(string: item.thumbnailURL ?? item.url)

        ZStack(alignment: .topTrailing) {
            if let url = imageURL {
                ThumbnailImageView(url: url, maxPixelSize: 360) {
                    Rectangle()
                        .fill(Color.skyPrimary.opacity(0.08))
                        .overlay { ProgressView().scaleEffect(0.5) }
                }
                .scaledToFill()
                .frame(minWidth: 0, minHeight: 0)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
            }

            VStack {
                Spacer()
                HStack {
                    if let age = ageText(for: item) {
                        Text(age)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                    Spacer()
                }
            }

            if item.type == .video {
                VStack {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.15))
            }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                .shadow(color: .black.opacity(0.4), radius: 2)
                .padding(6)
        }
        .onTapGesture(count: 2) {
            previewItem = item
        }
        .onTapGesture {
            if isSelected {
                viewModel.selectedIDs.remove(item.id)
            } else {
                viewModel.selectedIDs.insert(item.id)
            }
        }
    }

    private func filterLabel(_ f: MediaFilter, count: Int) -> String {
        "\(f.label) (\(count))"
    }

    private func ageText(for item: MediaItem) -> String? {
        item.ageText
    }

    private func loadInitial() async {
        initialLoadTask?.cancel()
        loadMoreTask?.cancel()
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        let task = Task {
            await viewModel.load(account: account, appPassword: appPassword, using: blueskyClient)
        }
        initialLoadTask = task
        await task.value
    }

    private func loadMore() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMore(account: account, appPassword: appPassword, using: blueskyClient)
        }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    private func refresh() async {
        guard accountStore.activeAccount != nil else { return }
        await loadInitial()
    }

    private func performDownload(to directory: URL) async {
        downloadTask?.cancel()
        let task = Task {
            await viewModel.downloadSelected(to: directory, handle: handle)
        }
        downloadTask = task
        await task.value
    }
}

private struct MediaPreviewView: View {
    let item: MediaItem
    let onDismiss: () -> Void

    var body: some View {
        if item.type == .video, let playlist = item.playlistURL.flatMap(URL.init) {
            VideoPlayerView(url: playlist, onDismiss: onDismiss)
        } else if let url = URL(string: item.url) {
            ImagePreviewView(url: url.absoluteString, onDismiss: onDismiss)
        }
    }
}

struct VideoPlayerView: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var player: AVPlayer?

    init(url: URL, onDismiss: @escaping () -> Void) {
        self.url = url
        self.onDismiss = onDismiss
    }

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                if let player {
                    AVPlayerControllerRepresentable(player: player)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                }
            }
            .onAppear {
                player = AVPlayer(url: url)
                player?.play()
            }
            .onDisappear {
                player?.pause()
            }
    }
}

private struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController()
        c.player = player
        c.showsPlaybackControls = true
        c.entersFullScreenWhenPlaybackBegins = true
        return c
    }

    func updateUIViewController(_: AVPlayerViewController, context _: Context) {}
}

private struct ImagePreviewView: View {
    let url: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                if let url = URL(string: url) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1, lastScale * value)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation {
                                    if scale > 1 {
                                        scale = 1
                                        offset = .zero
                                        lastScale = 1
                                        lastOffset = .zero
                                    } else {
                                        scale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                    } placeholder: {
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                }
            }
            .onTapGesture {
                if scale <= 1 { onDismiss() }
            }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
