import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Full compose view for creating, replying to, quoting, or editing posts.
/// Supports text, images (up to 4), GIFs (beta), video, alt text, reply controls
/// (who can reply), and thread-gate rules.
struct ComposePostView: View {
    @Bindable var viewModel: ComposePostViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var textViewRef: UITextView?
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                let activeReplyTo = viewModel.editReplyTo ?? viewModel.replyTo
                if activeReplyTo != nil || viewModel.quote != nil {
                    Section {
                        if let referencedPost = viewModel.referencedPost {
                            postPreviewRow(referencedPost)
                        } else {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(loc: "timeline.loading")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(verbatim: activeReplyTo != nil ? loc("profile.posts.replying_to") : loc("compose.quoting"))
                    }
                }

                Section {
                    WritingToolsTextView(text: $viewModel.postText, textViewRef: $textViewRef)
                        .frame(minHeight: 120)

                    HStack {
                        Spacer()
                        if viewModel.postText.count > 300 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Text("\(viewModel.postText.count)/300")
                            .font(.caption)
                            .foregroundStyle(viewModel.postText.count > 300 ? .red : .green)
                    }
                    .accessibilityLabel(loc("compose.char_count").replacingOccurrences(of: "{n}", with: "\(viewModel.postText.count)/300"))
                } header: {
                    Text(loc: "compose.text_section")
                }

                if let previewURL = viewModel.selectedGIFPreviewURL, !previewURL.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: URL(string: previewURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.quaternary)
                                    .frame(height: 120)
                            }
                            if !viewModel.selectedGIFTitle.isEmpty {
                                Text(viewModel.selectedGIFTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                viewModel.videoAttachment = nil
                                viewModel.selectedGIFPreviewURL = nil
                                viewModel.selectedGIFLinkURL = nil
                                viewModel.selectedGIFTitle = ""
                            } label: {
                                Label(loc("actions.remove"), systemImage: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text(loc: "compose.gif_selected")
                    }
                }

                imageAttachmentsSection
                replyControlsSection
                addMediaSection
            }
            .pageTitle(navigationTitleString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isPosting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(loc("compose.post")) {
                            Task {
                                await viewModel.post()
                                if viewModel.errorMessage == nil {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isPosting, !viewModel.selectedImages.isEmpty {
                    uploadProgressBar
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: .init(
                get: { viewModel.altEditIndex != nil },
                set: {
                    if !$0 {
                        viewModel.altEditIndex = nil
                    }
                }
            )) {
                if let index = viewModel.altEditIndex, index < viewModel.selectedImages.count {
                    altTextEditView(index: index)
                }
            }
            .alert(Text(loc: "compose.error"), isPresented: .constant(viewModel.errorMessage != nil)) {
                Button(loc("actions.ok")) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $viewModel.showGIFPicker) {
                GIFPickerView { gif in
                    Task { await viewModel.handleGIFSelection(gif) }
                }
            }
            .confirmationDialog(loc("compose.reply_controls"), isPresented: $viewModel.showReplyPicker) {
                Button(loc("compose.reply_everyone")) { viewModel.replyRule = nil }
                Button(loc("compose.reply_nobody")) { viewModel.replyRule = .noReply }
                Button(loc("compose.reply_following")) { viewModel.replyRule = .followingRule }
                Button(loc("compose.reply_mention")) { viewModel.replyRule = .mentionRule }
                Button(loc("compose.reply_list")) {
                    viewModel.showListPicker = true
                    Task { await viewModel.loadUserLists() }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $viewModel.showListPicker) {
                NavigationStack {
                    List(viewModel.userLists) { list in
                        Button {
                            if list.cid != nil {
                                viewModel.replyRule = .listRule(list: list.id)
                            }
                            viewModel.showListPicker = false
                        } label: {
                            listRowLabel(list)
                        }
                    }
                    .pageTitle(loc("compose.reply_list_pick"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loc("actions.cancel")) { viewModel.showListPicker = false }
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isScaling {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(loc("compose.image_scaling"))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .alert(loc("compose.image_resize_title"), isPresented: $viewModel.showImageResizeAlert, presenting: viewModel.pendingImageResize) { _ in
                Button(loc("compose.image_resize_scale")) {
                    viewModel.pendingImageResize?()
                    viewModel.showImageResizeAlert = false
                }
                Button(loc("actions.cancel"), role: .cancel) {
                    viewModel.showImageResizeAlert = false
                }
            } message: { _ in
                Text(loc("compose.image_resize_message"))
            }
            .task {
                await viewModel.loadReferencedPost()
                await viewModel.preloadEditData()
            }
        }
    }

    // MARK: - Section builders

    @ViewBuilder private var imageAttachmentsSection: some View {
        if !viewModel.selectedImages.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, _ in
                            VStack(spacing: 4) {
                                // Thumbnail with alt badge + tap to edit
                                ZStack(alignment: .bottomLeading) {
                                    if let uiImage = UIImage(data: viewModel.selectedImages[index].data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .contentShape(Rectangle())
                                            .onTapGesture { viewModel.altEditIndex = index }
                                    }

                                    // Alt-status badge
                                    if index < viewModel.imageAlts.count {
                                        if viewModel.imageAlts[index].isEmpty {
                                            Text("ALT")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                                                .padding(6)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                                .background(Circle().fill(.white).frame(width: 12, height: 12))
                                                .padding(6)
                                        }
                                    }

                                    // Remove button
                                    HStack {
                                        Spacer()
                                        VStack {
                                            Button {
                                                viewModel.selectedImages.remove(at: index)
                                                viewModel.imageAlts.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.red)
                                                    .background(Circle().fill(.ultraThinMaterial).frame(width: 24, height: 24))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(loc("compose.remove_image"))
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                            Spacer()
                                        }
                                    }
                                    .offset(x: 4, y: -4)
                                }

                                // Alt text preview below thumbnail
                                if index < viewModel.imageAlts.count, !viewModel.imageAlts[index].isEmpty {
                                    Text(viewModel.imageAlts[index])
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 100)
                                        .onTapGesture { viewModel.altEditIndex = index }
                                } else {
                                    Text(loc("compose.alt_placeholder"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100)
                                        .onTapGesture { viewModel.altEditIndex = index }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text(loc("compose.images_section"))
                    Spacer()
                    Text("\(viewModel.selectedImages.count)/\(viewModel.maxImages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var replyControlsSection: some View {
        Section {
            Label {
                HStack {
                    Text(loc("compose.reply_controls"))
                    Spacer()
                    Text(replyRuleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrowshape.turn.up.right.circle")
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.showReplyPicker = true }

            Toggle(loc("compose.allow_quoting"), isOn: $viewModel.allowQuoting)
        }
    }

    @MainActor private var addMediaSection: some View {
        Section {
            let addImagesText = loc("compose.add_images")
            PhotosPicker(selection: $viewModel.selectedItems, maxSelectionCount: viewModel.maxImages, matching: .images) {
                Label { Text(verbatim: addImagesText) } icon: { Image(systemName: "photo.on.rectangle.angled") }
            }
            .disabled(viewModel.selectedImages.count >= viewModel.maxImages || viewModel.videoAttachment != nil || viewModel.selectedGIFLinkURL != nil)
            .onChange(of: viewModel.selectedItems) { _, items in
                Task { await viewModel.loadImages(from: items) }
            }

            Button {
                viewModel.showGIFPicker = true
            } label: {
                HStack {
                    Label { Text(loc("compose.add_gif")) } icon: { Image(systemName: "play.rectangle") }
                    Spacer()
                    if viewModel.isDownloadingGIF {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            .disabled(viewModel.isDownloadingGIF || viewModel.videoAttachment != nil || viewModel.selectedGIFLinkURL != nil || !viewModel.selectedImages.isEmpty)
            .foregroundStyle(viewModel.videoAttachment != nil || viewModel.selectedGIFLinkURL != nil ? Color.skyPrimary : .primary)
        }
    }

    private func postPreviewRow(_ post: ThreadPostNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let author = post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
            PostAuthorHeader(
                author: author,
                createdAt: post.indexedAt ?? post.record?.createdAt,
                onOpenProfile: nil,
                avatarSize: 24
            )
            if let text = post.record?.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    lineLimit: 6
                )
            }
        }
    }

    // MARK: - Computed properties

    private var navigationTitleString: String {
        if viewModel.editPost != nil {
            return loc("post.edit")
        }
        if (viewModel.editReplyTo ?? viewModel.replyTo) != nil {
            return loc("compose.reply_title")
        }
        if viewModel.quote != nil {
            return loc("compose.quote_title")
        }
        return loc("compose.title")
    }

    private var replyRuleLabel: String {
        guard let replyRule = viewModel.replyRule else { return loc("compose.reply_everyone") }
        switch replyRule {
        case .noReply: return loc("compose.reply_nobody")
        case .mentionRule: return loc("compose.reply_mention")
        case .followingRule: return loc("compose.reply_following")
        case .listRule: return loc("compose.reply_list")
        }
    }

    private var replyRuleListID: String? {
        if case let .listRule(list) = viewModel.replyRule {
            return list
        }
        return nil
    }

    private func listRowLabel(_ list: BlueskyList) -> some View {
        HStack {
            Image(systemName: list.kind.symbolName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .foregroundStyle(.primary)
                if let count = list.memberCount {
                    let members = loc("compose.reply_list_count").replacingOccurrences(of: "{n}", with: "\(count)")
                    Text(verbatim: members)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if case .listRule = viewModel.replyRule, list.id == replyRuleListID {
                Image(systemName: "checkmark")
            }
        }
    }

    private var uploadProgressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: viewModel.uploadProgress ?? 0, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
            HStack {
                Text("\(Int((viewModel.uploadProgress ?? 0) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let uploadSpeed = viewModel.uploadSpeed {
                    Text(uploadSpeed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func altTextEditView(index: Int) -> some View {
        let altBinding = Binding(
            get: { index < viewModel.imageAlts.count ? viewModel.imageAlts[index] : "" },
            set: {
                if index < viewModel.imageAlts.count {
                    viewModel.imageAlts[index] = $0
                }
            }
        )
        return NavigationStack {
            VStack(spacing: 16) {
                if let uiImage = UIImage(data: viewModel.selectedImages[index].data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("\(loc("compose.alt_placeholder")) \(index + 1)/\(viewModel.selectedImages.count)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: altBinding)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("\(altBinding.wrappedValue.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { viewModel.altEditIndex = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.done")) { viewModel.altEditIndex = nil }
                }
            }
        }
    }
}

// MARK: - WritingTools UITextView Wrapper

private struct WritingToolsTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var textViewRef: UITextView?

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.textContainer.lineBreakMode = .byWordWrapping
        return tv
    }

    func updateUIView(_ uiView: UITextView, context _: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        textViewRef = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fittingSize = CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)
        let size = uiView.sizeThatFits(fittingSize)
        return CGSize(width: width, height: max(size.height, 120))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
