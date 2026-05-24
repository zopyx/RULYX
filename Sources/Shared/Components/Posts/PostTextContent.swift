import SwiftUI

struct PostTextContent: View {
    let text: String
    var onTapThread: (() -> Void)?
    var onOpenProfile: ((String) -> Void)?
    var font: Font = .body
    var lineLimit: Int?
    var foregroundStyle: Color = .primary

    var body: some View {
        let textContent = Text(mentionAttributedString(from: text))
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
        if let onTapThread {
            textContent
                .contentShape(Rectangle())
                .onTapGesture { onTapThread() }
        } else {
            textContent
        }
    }
}
