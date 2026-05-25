import SwiftUI

struct PostTextContent: View {
    let text: String
    var onTapThread: (() -> Void)?
    var onOpenProfile: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var font: Font = .body
    var lineLimit: Int?
    var foregroundStyle: Color = .primary
    @State private var attributedText: AttributedString

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

    var body: some View {
        let textContent = Text(attributedText)
            .font(font)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
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
