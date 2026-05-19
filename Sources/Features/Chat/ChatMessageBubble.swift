import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isOutgoing: Bool
    var onOpenProfile: ((String) -> Void)?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: message.sentAt)
    }

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(mentionAttributedString(from: message.text, isOutgoing: isOutgoing))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "mention", let handle = url.host {
                            onOpenProfile?(handle)
                            return .handled
                        }
                        return .systemAction
                    })

                HStack(spacing: 4) {
                    if !message.reactions.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(Array(message.reactions.prefix(3)), id: \.senderDID) { reaction in
                                Text(reaction.value)
                                    .font(.caption2)
                            }
                        }
                    }

                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(isOutgoing ? .white.opacity(0.7) : Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOutgoing ? Color.skyPrimary : Color(.systemGray5))
            .clipShape(BubbleShape(isOutgoing: isOutgoing))

            if !isOutgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func mentionAttributedString(from text: String, isOutgoing: Bool) -> AttributedString {
        var attributed = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?")
        else { return attributed }
        let nsRange = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: nsRange).reversed() {
            guard let range = Range(match.range, in: text),
                  let attrRange = Range(match.range, in: attributed) else { continue }
            let handle = String(text[range].dropFirst())
            attributed[attrRange].link = URL(string: "mention://\(handle)")
            attributed[attrRange].foregroundColor = isOutgoing ? Color.white : Color.skyPrimary
            attributed[attrRange].underlineStyle = .single
        }
        return attributed
    }
}

struct BubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path()

        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        let cornerRadius: CGFloat = isOutgoing ? radius : radius
        let tailSize: CGFloat = 6

        if isOutgoing {
            path.move(to: CGPoint(x: topLeft.x + cornerRadius, y: topLeft.y))
            path.addLine(to: CGPoint(x: topRight.x - cornerRadius, y: topRight.y))
            path.addQuadCurve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadius), control: topRight)
            path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadius - tailSize))
            path.addQuadCurve(to: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y - tailSize), control: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y - tailSize))
            path.addLine(to: CGPoint(x: rect.midX + tailSize, y: bottomRight.y - tailSize))
            path.addLine(to: CGPoint(x: rect.midX, y: bottomRight.y))
            path.addLine(to: CGPoint(x: rect.midX - tailSize, y: bottomRight.y - tailSize))
            path.addLine(to: CGPoint(x: bottomLeft.x + cornerRadius, y: bottomLeft.y - tailSize))
            path.addQuadCurve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadius - tailSize), control: bottomLeft)
            path.addLine(to: CGPoint(x: bottomLeft.x, y: topLeft.y + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: topLeft.x + cornerRadius, y: topLeft.y), control: topLeft)
        } else {
            path.move(to: CGPoint(x: topLeft.x + cornerRadius + tailSize, y: topLeft.y))
            path.addLine(to: CGPoint(x: topRight.x - cornerRadius, y: topRight.y))
            path.addQuadCurve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadius), control: topRight)
            path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y), control: bottomRight)
            path.addLine(to: CGPoint(x: bottomLeft.x + cornerRadius, y: bottomLeft.y))
            path.addQuadCurve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadius), control: bottomLeft)
            path.addLine(to: CGPoint(x: bottomLeft.x, y: topLeft.y + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: topLeft.x + cornerRadius + tailSize, y: topLeft.y), control: topLeft)
        }

        path.closeSubpath()
        return path
    }
}
