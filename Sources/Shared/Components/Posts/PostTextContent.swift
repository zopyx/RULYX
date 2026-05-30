import SwiftUI

// MARK: - PostTextContent

/// Renders post text as an `AttributedString` with tap-handling for mentions
/// (via `mention://` URL scheme) and external links.
///
/// When `onTapThread` is provided, the entire text area becomes tappable for
/// navigating to the post thread. Links and mentions are still intercepted
/// via `OpenURLAction` before the tap gesture fires.
struct PostTextContent: View {
    /// The raw post text containing mentions and links.
    let text: String
    /// Triggered when the post body is tapped (navigate to thread).
    var onTapThread: (() -> Void)?
    /// Triggered when a mention link is tapped, passing the handle.
    var onOpenProfile: ((String) -> Void)?
    /// Triggered when an external URL is tapped.
    var onOpenURL: ((URL) -> Void)?
    /// Font for the post text.
    var font: Font = .body
    /// Optional line limit for truncation.
    var lineLimit: Int?
    /// Foreground color for the text.
    var foregroundStyle: Color = .primary
    /// The attributed string built from the raw text.
    @State private var attributedText: AttributedString

    // MARK: - Init

    init(
        text: String,
        onTapThread: (() -> Void)? = nil,
        onOpenProfile: ((String) -> Void)? = nil,
        onOpenURL: ((URL) -> Void)? = nil,
        font: Font = .body,
        lineLimit: Int? = nil,
        foregroundStyle: Color = .primary
    ) {
        self.text = text
        self.onTapThread = onTapThread
        self.onOpenProfile = onOpenProfile
        self.onOpenURL = onOpenURL
        self.font = font
        self.lineLimit = lineLimit
        self.foregroundStyle = foregroundStyle
        _attributedText = State(initialValue: postAttributedString(from: text))
    }

    // MARK: - Body

    var body: some View {
        let textContent = Text(attributedText)
            .font(font)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                // Intercept mention:// URLs to navigate to profiles
                if url.scheme == "mention", let handle = url.host {
                    onOpenProfile?(handle)
                    return .handled
                }
                if let onOpenURL {
                    onOpenURL(url)
                    return .handled
                }
                return .systemAction
            })
            .onChange(of: text) {
                attributedText = postAttributedString(from: text)
            }
        if let onTapThread {
            textContent
                .contentShape(Rectangle())
                .onTapGesture { onTapThread() }
        } else {
            textContent
        }
    }
}

/// Converts @mentions and URLs in post text to tappable attributed links.
func postAttributedString(from text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard text.contains("@") || text.contains("://") || text.contains("www.") else { return attributed }

    let nsRange = NSRange(text.startIndex..., in: text)

    let mentionRegex = MentionTextRegex.shared
    for match in mentionRegex.matches(in: text, range: nsRange).reversed() {
        guard let range = Range(match.range, in: text),
              let attrRange = Range(match.range, in: attributed) else { continue }
        let handle = String(text[range].dropFirst())
        attributed[attrRange].link = URL(string: "mention://\(handle)")
        attributed[attrRange].foregroundColor = Color.skyPrimary
        attributed[attrRange].underlineStyle = .single
    }

    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        for match in detector.matches(in: text, range: nsRange).reversed() {
            guard let url = match.url,
                  let attrRange = Range(match.range, in: attributed) else { continue }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = Color.skyPrimary
            attributed[attrRange].underlineStyle = .single
        }
    }

    return attributed
}

/// Regex for matching @mention patterns in post text.
private enum MentionTextRegex {
    static let shared = try! NSRegularExpression(
        pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?"
    )
}
