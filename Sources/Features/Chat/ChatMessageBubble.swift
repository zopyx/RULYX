import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isOutgoing: Bool

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: message.sentAt)
    }

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isOutgoing ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)

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
