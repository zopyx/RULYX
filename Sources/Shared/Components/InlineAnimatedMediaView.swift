import SwiftUI
import WebKit

struct InlineAnimatedMediaView: View {
    let url: URL
    var allowsInteraction: Bool = false
    var height: CGFloat = 200
    var cornerRadius: CGFloat = 8

    var body: some View {
        InlineAnimatedMediaWebView(url: url, allowsInteraction: allowsInteraction)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .allowsHitTesting(allowsInteraction)
            .accessibilityHidden(!allowsInteraction)
    }
}

private struct InlineAnimatedMediaWebView: UIViewRepresentable {
    let url: URL
    let allowsInteraction: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = allowsInteraction

        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isUserInteractionEnabled = allowsInteraction
        guard webView.url != url else { return }
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        let ext = url.pathExtension.lowercased()
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
            <body><img src="\(url.absoluteString)" /></body>
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
                <source src="\(url.absoluteString)">
            </video>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            webView.load(URLRequest(url: url))
        }
    }
}
