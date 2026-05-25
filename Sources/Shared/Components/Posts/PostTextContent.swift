import SwiftUI

struct PostTextContent: View {
    let text: String
    var onTapThread: (() -> Void)?
    var onOpenProfile: ((String) -> Void)?
    var font: Font = .body
    var lineLimit: Int?
    var foregroundStyle: Color = .primary
    @State private var attributedText: AttributedString

    init(
        text: String,
        onTapThread: (() -> Void)? = nil,
        onOpenProfile: ((String) -> Void)? = nil,
        font: Font = .body,
        lineLimit: Int? = nil,
        foregroundStyle: Color = .primary
    ) {
        self.text = text
        self.onTapThread = onTapThread
        self.onOpenProfile = onOpenProfile
        self.font = font
        self.lineLimit = lineLimit
        self.foregroundStyle = foregroundStyle
        _attributedText = State(initialValue: mentionAttributedString(from: text))
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
                return .systemAction
            })
            .onChange(of: text) {
                attributedText = mentionAttributedString(from: text)
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
