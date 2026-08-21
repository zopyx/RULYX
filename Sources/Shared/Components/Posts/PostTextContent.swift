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
        // Use cached value if available, else empty until async load (T04)
        _attributedText = State(initialValue: PostTextCache.shared.cachedSync(text) ?? AttributedString(text))
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
            .task(id: text) {
                if let cached = PostTextCache.shared.cachedSync(text) {
                    attributedText = cached
                } else {
                    let result = await PostTextCache.shared.attributedString(for: text)
                    attributedText = result
                }
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
    static let shared: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?"
            )
        } catch {
            AppLogger.persistence.error("Failed to compile mention regex: \(error)")
            return NSRegularExpression()
        }
    }()
}

// MARK: - PostTextCache (T04)

/// Caches attributed strings off main thread to keep scrolling smooth.
/// `NSDataDetector` + `NSRegularExpression` are ~1–3 ms per post on main; with 50 rows that blocks scroll.
final class PostTextCache: @unchecked Sendable {
    static let shared = PostTextCache()
    private let cache = NSCache<NSString, NSStringWrapper>()
    private let queue = DispatchQueue(label: "PostTextCache", qos: .userInitiated)
    private final class NSStringWrapper: NSObject { let value: AttributedString
        init(_ v: AttributedString) {
            value = v
        }
    }

    func cachedSync(_ text: String) -> AttributedString? {
        cache.object(forKey: text as NSString)?.value
    }

    func attributedString(for text: String) async -> AttributedString {
        if let cached = cachedSync(text) {
            return cached
        }
        let result = await Task.detached(priority: .userInitiated) {
            postAttributedString(from: text)
        }.value
        cache.setObject(NSStringWrapper(result), forKey: text as NSString)
        return result
    }
}
