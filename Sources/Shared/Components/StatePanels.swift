import MessageUI
import PhotosUI
import SwiftUI

// MARK: - LoadingPanel

/// A full-width loading indicator with a message and progress spinner.
/// Used to fill content areas while data is being fetched.
struct LoadingPanel: View {
    /// The localized message shown alongside the spinner.
    let message: String
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

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

// MARK: - EmptyStatePanel

/// A centered empty-state placeholder with a tray icon, title, and optional message.
/// Used when a list or section has no content.
struct EmptyStatePanel: View {
    /// The primary title text.
    let title: String
    /// An optional descriptive message shown below the title.
    let message: String

    // MARK: - Init

    init(title: String, message: String = "") {
        self.title = title
        self.message = message
    }

    // MARK: - Body

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

// MARK: - ErrorRetryBanner

/// A card-style banner showing an error message with a retry button.
/// Uses warning icon and orange accent color.
struct ErrorRetryBanner: View {
    /// The error message to display.
    let message: String
    /// Closure invoked when the retry button is tapped.
    let retry: () -> Void

    // MARK: - Body

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
                Label("actions.retry", systemImage: "arrow.clockwise")
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

// MARK: - BatchProgressCard

/// A progress card for batch operations (add, block, mute) showing completion ratio,
/// current handle being processed, and an optional cancel button.
struct BatchProgressCard: View {
    /// Title of the batch operation.
    let title: String
    /// Number of items processed so far.
    let completedCount: Int
    /// Total number of items to process.
    let totalCount: Int
    /// Handle of the item currently being processed, if any.
    let currentHandle: String?
    /// Optional cancel button action. When nil, the cancel button is hidden.
    let onCancel: (() -> Void)?

    // MARK: - Init

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

    // MARK: - Body

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
                        Label("actions.cancel", systemImage: "xmark.circle")
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

// MARK: - StatusChip

/// A small capsule-shaped badge indicating a status.
/// Supports neutral, positive, warning, destructive, and info styles.
/// Uses iOS 26 glass effect when available, falling back to solid background.
struct StatusChip: View {
    /// Visual style options for the chip.
    enum Style {
        /// Default gray appearance.
        case neutral
        /// Green for success states.
        case positive
        /// Orange for warning states.
        case warning
        /// Red for destructive/error states.
        case destructive
        /// Blue for informational states.
        case info
    }

    /// The text displayed inside the chip.
    let text: String
    /// The visual style determining color.
    let style: Style

    // MARK: - Body

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

    // MARK: - Private Helpers

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

// MARK: - OnboardingRow

/// A row with icon, title, and description, used in onboarding or feature-intro screens.
struct OnboardingRow: View {
    /// SF Symbol name for the icon.
    let icon: String
    /// Tint color for the icon.
    let color: Color
    /// The row's title text.
    let title: String
    /// Descriptive text below the title.
    let description: String

    // MARK: - Body

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

// MARK: - HelpInfoButton

/// A plain info-circle button that triggers the given action.
/// Placed next to section headers to show explanatory content.
struct HelpInfoButton: View {
    /// Action to perform when tapped.
    let action: () -> Void
    /// Accessibility label for the button.
    let accessibilityLabel: String

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle.fill")
                .font(.body)
                .foregroundStyle(Color.skyPrimary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - ToolbarCloseButton

/// Standard dismiss/close button using `xmark.circle.fill`.
/// Uses `@Environment(\.dismiss)` by default or a custom action when provided.
struct ToolbarCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    /// Optional custom action. When nil, uses the environment dismiss.
    let action: (() -> Void)?

    // MARK: - Init

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        Button {
            action?() ?? dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loc("actions.dismiss"))
    }
}

// MARK: - SimplifiedReportSheet

/// A two-tab report sheet: "Submit" (report via API) and "Contact" (email support with attachments).
/// Allows selecting a reason, writing evidence text, and attaching up to 5 photos.
struct SimplifiedReportSheet: View {
    /// Navigation title for the sheet.
    let title: String
    /// The selected report reason.
    @Binding var selectedReason: ModerationReportReasonType
    /// Free-form evidence text.
    @Binding var evidenceText: String
    /// Whether a submit is in progress.
    let isSubmitting: Bool
    /// Closure that creates the support email draft.
    let makeSupportDraft: () -> SupportEmailDraft
    /// Dismisses the sheet without action.
    let onCancel: () -> Void
    /// Submits the report via the API.
    let onSubmit: () -> Void

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var supportImages: [UIImage] = []
    @State private var mailDraft: SupportEmailDraft?
    @State private var isShowingMailUnavailableAlert = false
    @State private var showSubmitHelp = false
    @State private var showContactHelp = false
    @State private var reportTab = ReportTab.submit

    /// Tabs for choosing report submission method.
    private enum ReportTab: String, CaseIterable {
        /// Submit report via the Bluesky API.
        case submit
        /// Contact support via email.
        case contact
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(selection: $reportTab) {
                    Text(loc("report.option_submit.title")).tag(ReportTab.submit)
                    Text(loc("report.option_contact.title")).tag(ReportTab.contact)
                } label: {
                    Text(loc("report.tab_label"))
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    Text(loc("profile.report.reason_explanation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("profile.report.reason", selection: $selectedReason) {
                        ForEach(ModerationReportReasonType.allCases) { reason in
                            Text(reason.localizedTitle)
                                .tag(reason)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if reportTab == .submit {
                    Section {
                        ZStack(alignment: .topLeading) {
                            if evidenceText.isEmpty {
                                Text(loc: "profile.report.evidence_placeholder")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                            }
                            TextEditor(text: $evidenceText)
                                .frame(minHeight: 100)
                                .foregroundStyle(.primary)
                        }

                        Button(action: onSubmit) {
                            HStack {
                                Spacer()
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(loc: "profile.report.submit")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isSubmitting)
                        .listRowBackground(isSubmitting ? Color.gray : Color.red)
                        .foregroundStyle(.white)
                    }
                } else {
                    Section {
                        PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                            Label("report.support.attachment.add", systemImage: "paperclip")
                        }

                        if !supportImages.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(supportImages.indices, id: \.self) { index in
                                    Image(uiImage: supportImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                supportImages.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                                    .background(Circle().fill(.white.opacity(0.9)))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(2)
                                        }
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        Button {
                            guard MFMailComposeViewController.canSendMail() else {
                                isShowingMailUnavailableAlert = true
                                return
                            }
                            mailDraft = makeSupportDraft()
                        } label: {
                            HStack {
                                Spacer()
                                Label("report.support.email", systemImage: "envelope")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(isSubmitting)
                        .listRowBackground(isSubmitting ? Color.gray : Color.red)
                        .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel"), action: onCancel)
                        .disabled(isSubmitting)
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }

                Task {
                    var images: [UIImage] = []
                    for item in newItems {
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data)
                        else { continue }
                        images.append(image)
                    }
                    await MainActor.run {
                        supportImages += images
                    }
                }
            }
            .sheet(item: $mailDraft) { draft in
                SupportMailComposeView(
                    draft: draft,
                    attachmentImages: supportImages
                )
            }
            .alert("report.support.mail_unavailable", isPresented: $isShowingMailUnavailableAlert) {
                Button("actions.ok") {}
            }
            .sheet(isPresented: $showSubmitHelp) {
                helpSheet(
                    title: loc("report.option_submit.title"),
                    text: loc("report.option_submit.help")
                )
            }
            .sheet(isPresented: $showContactHelp) {
                helpSheet(
                    title: loc("report.option_contact.title"),
                    text: loc("report.option_contact.help")
                )
            }
        }
    }

    /// Builds a help sheet with a navigation stack and close button.
    private func helpSheet(title: String, text: String) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(text)
                        .font(.body)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
        }
    }
}

// MARK: - SupportEmailDraft

/// An identifiable wrapper for the subject, body, and optional attachments of a support email.
struct SupportEmailDraft: Identifiable {
    /// Email subject line.
    let subject: String
    /// HTML email body.
    let body: String

    var id: String {
        subject + body
    }

    /// Generate an HTML email body with an intro paragraph, a labeled field table, and optional footer.
    static func htmlBody(intro: String, fields: [(String, String)], footer: String = "") -> String {
        let fieldRows = fields.map { label, value in
            let safeValue = value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            return """
            <tr>
                <td style="padding: 8px 16px; font-weight: 600; color: #555; white-space: nowrap; vertical-align: top; border-bottom: 1px solid #eee; width: 120px;">\(label)</td>
                <td style="padding: 8px 16px; color: #333; vertical-align: top; border-bottom: 1px solid #eee;">\(safeValue)</td>
            </tr>
            """
        }.joined()

        let footerBlock = footer.isEmpty ? "" : """
            <p style="font-size: 15px; color: #555; line-height: 1.5; margin: 0 0 8px 0;">\(footer)</p>
        """

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#f4f4f7;margin:0;padding:24px;">
        <table style="max-width:560px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 6px rgba(0,0,0,0.08);" cellpadding="0" cellspacing="0">
        <tr><td style="padding:28px 24px 0 24px;">
        <p style="font-size:15px;color:#333;line-height:1.6;margin:0 0 16px 0;">Hello Bluesky Support,</p>
        <p style="font-size:15px;color:#333;line-height:1.6;margin:0 0 16px 0;">\(intro)</p>
        </td></tr>
        <tr><td style="padding:0 24px;">
        <table style="width:100%;border-collapse:collapse;" cellpadding="0" cellspacing="0">\(fieldRows)</table>
        </td></tr>
        <tr><td style="padding:20px 24px 28px 24px;">
        \(footerBlock)
        <p style="font-size:15px;color:#333;line-height:1.6;margin:0 0 8px 0;">Thank you for your help.</p>
        <p style="font-size:15px;color:#333;line-height:1.6;margin:0;">Best regards,<br>RULYX User</p>
        </td></tr>
        <tr><td style="padding:14px 24px;background:#f8f8fa;border-top:1px solid #eee;">
        <p style="font-size:11px;color:#999;margin:0;text-align:center;">Sent from RULYX — Bluesky Moderation Tool for iOS</p>
        </td></tr>
        </table></body></html>
        """
    }
}

// MARK: - SupportMailComposeView

/// Wraps `MFMailComposeViewController` to send support email with optional JPEG attachments.
private struct SupportMailComposeView: UIViewControllerRepresentable {
    /// The email draft containing subject and body.
    let draft: SupportEmailDraft
    /// Optional images to attach as JPEGs.
    let attachmentImages: [UIImage]

    @Environment(\.dismiss) private var dismiss

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(["support@bluesky.com"])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: true)

        for (index, image) in attachmentImages.enumerated() {
            if let data = image.jpegData(compressionQuality: 0.9) {
                controller.addAttachmentData(
                    data,
                    mimeType: "image/jpeg",
                    fileName: "support-attachment-\(index + 1).jpg"
                )
            }
        }

        return controller
    }

    func updateUIViewController(_: MFMailComposeViewController, context _: Context) {}

    /// Coordinator handling mail compose delegate callbacks.
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _: MFMailComposeViewController,
            didFinishWith _: MFMailComposeResult,
            error _: Error?
        ) {
            dismiss()
        }
    }
}

// MARK: - String Helpers

extension String {
    /// Returns `nil` if the string is empty or whitespace-only.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
extension ModerationReportReasonType {
    /// Localized title for each report reason.
    var localizedTitle: String {
        switch self {
        case .harassmentTargeted:
            loc("profile.report.reason.harassment_targeted")
        case .harassmentHateSpeech:
            loc("profile.report.reason.harassment_hate_speech")
        case .harassmentDoxxing:
            loc("profile.report.reason.harassment_doxxing")
        case .harassmentTroll:
            loc("profile.report.reason.harassment_troll")
        case .harassmentOther:
            loc("profile.report.reason.harassment_other")
        }
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
