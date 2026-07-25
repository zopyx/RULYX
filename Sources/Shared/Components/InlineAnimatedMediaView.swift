import SwiftUI
import WebKit

// MARK: - InlineAnimatedMediaView

/// Renders animated media (GIF, video) inline using a `WKWebView` with transparent background.
/// Supports image formats (gif, jpg, png, webp) and video formats (mp4, webm, mov, m4v).
/// When `allowsInteraction` is true, the web view is user-interactable (e.g. for pause/play).
struct InlineAnimatedMediaView: View {
    /// The URL of the media file to display.
    let url: URL
    /// Whether the web view should allow user interaction.
    var allowsInteraction: Bool = false
    /// The height of the media area.
    var height: CGFloat = 200
    /// Corner radius applied to the media area.
    var cornerRadius: CGFloat = 8

    // MARK: - Body

    var body: some View {
        InlineAnimatedMediaWebView(url: url, allowsInteraction: allowsInteraction)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .allowsHitTesting(allowsInteraction)
            .accessibilityHidden(!allowsInteraction)
    }
}

// MARK: - InlineAnimatedMediaWebView

/// `UIViewRepresentable` wrapping a `WKWebView` configured for inline media playback.
///
/// Security hardening (the media URL originates from remote, untrusted post
/// content):
/// - The URL is HTML-escaped before being embedded into the page template, so
///   a crafted URL cannot break out of the `src` attribute and inject markup.
/// - JavaScript is disabled — `<img>`/`<video>` rendering does not need it.
/// - A non-persistent data store is used (no cookies, cache, or storage shared
///   with other web views).
/// - All navigation requests are cancelled by the navigation delegate: the
///   embedded page must never follow links or redirects to other content.
private struct InlineAnimatedMediaWebView: UIViewRepresentable {
    let url: URL
    let allowsInteraction: Bool

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = allowsInteraction
        webView.navigationDelegate = context.coordinator

        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context _: Context) {
        webView.isUserInteractionEnabled = allowsInteraction
        guard webView.url != url else { return }
        loadContent(in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    /// Cancels every navigation action: the media page is fully self-contained
    /// and must never navigate away (link clicks, redirects, JS-less tricks).
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    // MARK: - Private Helpers

    /// Escapes a URL string for safe embedding inside a double-quoted HTML
    /// attribute value. Prevents attribute-breakout HTML injection from
    /// untrusted remote URLs.
    private func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Construct an HTML page embedding the media file with transparent background and cover sizing.
    private func loadContent(in webView: WKWebView) {
        let ext = url.pathExtension.lowercased()
        let safeURL = htmlEscaped(url.absoluteString)
        if ["gif", "jpg", "jpeg", "png", "webp"].contains(ext) {
            let html = """
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
            html,body{margin:0;background:transparent;overflow:hidden}
            body{display:flex;align-items:center;justify-content:center}
            img{width:100%;height:100%;object-fit:cover}
            </style>
            </head>
            <body><img src="\(safeURL)" /></body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        } else if ["mp4", "webm", "mov", "m4v"].contains(ext) {
            let html = """
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
            html,body{margin:0;background:transparent;overflow:hidden}
            video{width:100%;height:100%;object-fit:cover}
            </style>
            </head>
            <body>
            <video autoplay muted loop playsinline>
                <source src="\(safeURL)">
            </video>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            // Unknown extension: load directly, still under the locked-down
            // configuration (JavaScript disabled, ephemeral store, navigation
            // delegate cancels any subsequent navigation).
            webView.load(URLRequest(url: url))
        }
    }
}
