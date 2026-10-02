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
    /// Rich-text facets for the post. When present, mentions/links are rendered
    /// from the facet byte ranges and target DIDs/URIs (no handle resolution needed
    /// on tap); when `nil`, mentions/links are detected via regex as a fallback.
    let facets: [RichFacet]?
    /// Triggered when the post body is tapped (navigate to thread).
    var onTapThread: (() -> Void)?
    /// Triggered when a mention link is tapped, passing the handle or DID.
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
        facets: [RichFacet]? = nil,
        onTapThread: (() -> Void)? = nil,
        onOpenProfile: ((String) -> Void)? = nil,
        onOpenURL: ((URL) -> Void)? = nil,
        font: Font = .body,
        lineLimit: Int? = nil,
        foregroundStyle: Color = .primary
    ) {
        self.text = text
        self.facets = facets
        self.onTapThread = onTapThread
        self.onOpenProfile = onOpenProfile
        self.onOpenURL = onOpenURL
        self.font = font
        self.lineLimit = lineLimit
        self.foregroundStyle = foregroundStyle
        // Facet rendering is cheap (no regex/data detection), so build it inline;
        // regex-based rendering goes through the cache (T04).
        if let facets, !facets.isEmpty {
            _attributedText = State(initialValue: postAttributedString(from: text, facets: facets))
        } else {
            _attributedText = State(initialValue: PostTextCache.shared.cachedSync(text) ?? AttributedString(text))
        }
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
                // Intercept mention links to navigate to profiles. The target is a DID when
                // rendered from facets, a handle when rendered by the regex fallback.
                if let target = MentionLink.target(from: url) {
                    onOpenProfile?(target)
                    return .handled
                }
                if let onOpenURL {
                    onOpenURL(url)
                    return .handled
                }
                return .systemAction
            })
            .task(id: text) {
                // Refresh on row recycling: a reused view may now show a different post.
                if let facets, !facets.isEmpty {
                    attributedText = postAttributedString(from: text, facets: facets)
                } else if let cached = PostTextCache.shared.cachedSync(text) {
                    attributedText = cached
                } else {
                    let result = await PostTextCache.shared.attributedString(for: text)
                    attributedText = result
                }
            }
        if let onTapThread {
            // The "open thread" tap sits *behind* the text (as its background): a gesture
            // attached to the text itself would win over the link handling the mentions inside
            // it need, while a tap that misses a link falls through to this layer.
            textContent
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onTapThread() }
                }
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
        attributed[attrRange].link = MentionLink.url(for: handle)
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

/// Builds the attributed string from a post's rich-text facets.
/// Mention facets become mention links carrying the target DID (already known, so opening the
/// profile needs no handle resolution); link facets become their URL. Invalid or out-of-range
/// facets are skipped.
func postAttributedString(from text: String, facets: [RichFacet]) -> AttributedString {
    var attributed = AttributedString(text)
    for facet in facets {
        guard facet.index.byteEnd > facet.index.byteStart,
              let lowerTextIndex = text.utf8.index(
                  text.startIndex,
                  offsetBy: facet.index.byteStart,
                  limitedBy: text.endIndex
              ),
              let upperTextIndex = text.utf8.index(
                  lowerTextIndex,
                  offsetBy: facet.index.byteEnd - facet.index.byteStart,
                  limitedBy: text.endIndex
              ),
              let lower = AttributedString.Index(lowerTextIndex, within: attributed),
              let upper = AttributedString.Index(upperTextIndex, within: attributed)
        else { continue }
        let attrRange = lower ..< upper
        guard let feature = facet.features.first(where: { $0.did != nil || $0.uri != nil }) else { continue }
        if let did = feature.did {
            attributed[attrRange].link = MentionLink.url(for: did)
        } else if let uri = feature.uri, let url = URL(string: uri) {
            attributed[attrRange].link = url
        } else {
            continue
        }
        attributed[attrRange].foregroundColor = Color.skyPrimary
        attributed[attrRange].underlineStyle = .single
    }
    return attributed
}

// MARK: - MentionLink

/// The custom `mention://` link used to make handles and mentions tappable.
///
/// The target travels in the **path**, never in the host: a DID contains colons, and
/// `URL(string: "mention://did:plc:…")` is not a valid URL at all (the colon reads as a port
/// separator) — it returns `nil`, so such a mention stayed plain, untappable text while still
/// being styled like a link.
enum MentionLink {
    /// Link for a mention target: a DID (facet rendering) or a handle (regex fallback).
    static func url(for target: String) -> URL? {
        URL(string: "mention:///\(target)")
    }

    /// The target carried by `url`, or `nil` when it is not a mention link.
    /// Host-form links are still understood, so older attributed strings keep working.
    static func target(from url: URL) -> String? {
        guard url.scheme == "mention" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? url.host : path
    }
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
