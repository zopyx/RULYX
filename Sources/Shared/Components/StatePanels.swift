import MessageUI
import PhotosUI
import SwiftUI

struct LoadingPanel: View {
    let message: String
    @EnvironmentObject private var localizationManager: LocalizationManager

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

struct EmptyStatePanel: View {
    let title: String
    let message: String

    init(title: String, message: String = "") {
        self.title = title
        self.message = message
    }

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

struct ErrorRetryBanner: View {
    let message: String
    let retry: () -> Void

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
            .accessibilityHint("common.retry.hint")
        }
        .padding()
        .appCardStyle(cornerRadius: 12, style: .subtle)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

struct BatchProgressCard: View {
    let title: String
    let completedCount: Int
    let totalCount: Int
    let currentHandle: String?
    let onCancel: (() -> Void)?

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
                    .accessibilityLabel("actions.cancel")
                }
            }
        }
        .padding()
        .appCardStyle(cornerRadius: 12, style: .subtle)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityHint("common.progress.hint")
    }
}

struct StatusChip: View {
    enum Style {
        case neutral, positive, warning, destructive, info
    }

    let text: String
    let style: Style

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

struct HelpSection: View {
    let title: String
    let bulletPoints: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.subheading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bulletPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .appFont(.caption)
                            .foregroundStyle(Color.skyPrimary)
                            .frame(width: 16, height: 16)
                        Text(point)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .appCardStyle(cornerRadius: 12, style: .subtle)
    }
}

struct OnboardingRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

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
        .accessibilityHint("common.status.hint")
        .padding(.vertical, 8)
    }
}

struct SimplifiedReportSheet: View {
    let title: String
    @Binding var selectedReason: ModerationReportReasonType
    @Binding var evidenceText: String
    let isSubmitting: Bool
    let makeSupportDraft: () -> SupportEmailDraft
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var supportImage: UIImage?
    @State private var mailDraft: SupportEmailDraft?
    @State private var isShowingMailUnavailableAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("profile.report.reason", selection: $selectedReason) {
                        ForEach(ModerationReportReasonType.allCases) { reason in
                            Text(reason.localizedTitle)
                                .tag(reason)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("profile.report.reason")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if evidenceText.isEmpty {
                            Text("profile.report.evidence_placeholder")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $evidenceText)
                            .frame(minHeight: 100)
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("profile.report.evidence")
                }

                Section {
                    Button(action: onSubmit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("profile.report.submit")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting)
                    .listRowBackground(isSubmitting ? Color.gray : Color.red)
                    .foregroundStyle(.white)
                }

                Section {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("report.support.attachment.add", systemImage: "paperclip")
                    }

                    if let supportImage {
                        HStack(spacing: 12) {
                            Image(uiImage: supportImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("report.support.attachment")
                                    .appFont(.subheading)
                                Button(role: .destructive) {
                                    selectedPhotoItem = nil
                                    self.supportImage = nil
                                } label: {
                                    Label("report.support.attachment.remove", systemImage: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button {
                        guard MFMailComposeViewController.canSendMail() else {
                            isShowingMailUnavailableAlert = true
                            return
                        }
                        mailDraft = makeSupportDraft()
                    } label: {
                        Label("report.support.email", systemImage: "envelope")
                    }
                    .disabled(isSubmitting)
                } header: {
                    Text("report.support.section")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "actions.cancel"), action: onCancel)
                        .disabled(isSubmitting)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else {
                    supportImage = nil
                    return
                }

                Task {
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data)
                    else { return }
                    await MainActor.run {
                        supportImage = image
                    }
                }
            }
            .sheet(item: $mailDraft) { draft in
                SupportMailComposeView(
                    draft: draft,
                    attachmentImage: supportImage
                )
            }
            .alert("report.support.mail_unavailable", isPresented: $isShowingMailUnavailableAlert) {
                Button("actions.ok") {}
            }
        }
    }
}

struct SupportEmailDraft: Identifiable {
    let subject: String
    let body: String

    var id: String {
        subject + body
    }

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

private struct SupportMailComposeView: UIViewControllerRepresentable {
    let draft: SupportEmailDraft
    let attachmentImage: UIImage?

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(["support@bluesky.com"])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: true)
        if let attachmentImage,
           let data = attachmentImage.jpegData(compressionQuality: 0.9)
        {
            controller.addAttachmentData(
                data,
                mimeType: "image/jpeg",
                fileName: "support-attachment.jpg"
            )
        }
        return controller
    }

    func updateUIViewController(_: MFMailComposeViewController, context _: Context) {}

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

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
extension ModerationReportReasonType {
    var localizedTitle: String {
        switch self {
        case .harassmentTargeted:
            String(localized: "profile.report.reason.harassment_targeted")
        case .harassmentHateSpeech:
            String(localized: "profile.report.reason.harassment_hate_speech")
        case .harassmentDoxxing:
            String(localized: "profile.report.reason.harassment_doxxing")
        case .harassmentTroll:
            String(localized: "profile.report.reason.harassment_troll")
        case .harassmentOther:
            String(localized: "profile.report.reason.harassment_other")
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
