import SwiftUI

// MARK: - ChatMessageBubble

/// A single chat message bubble with mention link detection, reactions,
/// a tail shape that flips for outgoing vs. incoming messages, and a
/// context menu for reacting, copying, or deleting the message.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let isOutgoing: Bool
    var onOpenProfile: ((String) -> Void)?
    var onRetry: (() -> Void)?
    var onDelete: (() -> Void)?
    var onReact: ((String) -> Void)?
    var onReactionTap: ((String) -> Void)?

    /// Common emoji reactions shown in the picker.
    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    @State private var showReactionPicker = false

    private var isPending: Bool {
        message.id.hasPrefix("pending-")
    }

    private var hasFailed: Bool {
        message.rev == "failed"
    }

    /// Shared time-only formatter for timestamps.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
        return f
    }()

    /// Formatted time string for the message timestamp.
    private var timeString: String {
        Self.timeFormatter.string(from: message.sentAt)
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom) {
            if isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                // Message bubble content
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

                // Footer: status indicators + timestamp
                HStack(spacing: 4) {
                    if isPending {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(isOutgoing ? .white.opacity(0.5) : Color(.tertiaryLabel))
                    }

                    if hasFailed {
                        Button {
                            onRetry?()
                        } label: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(isOutgoing ? .white.opacity(0.7) : Color(.tertiaryLabel))
                }

                // Reactions row (below the bubble, outside the background)
                if !message.reactions.isEmpty {
                    let grouped = Dictionary(grouping: message.reactions, by: { $0.value })
                    HStack(spacing: 4) {
                        ForEach(Array(grouped.keys.sorted()), id: \.self) { emoji in
                            reactionPill(emoji: emoji, count: grouped[emoji]!.count)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOutgoing ? Color.skyPrimary : Color(.systemGray5))
            .opacity(isPending ? 0.6 : 1.0)
            .clipShape(BubbleShape(isOutgoing: isOutgoing))
            .contextMenu {
                // Reaction picker
                Menu {
                    ForEach(Self.commonReactions, id: \.self) { emoji in
                        Button {
                            onReact?(emoji)
                        } label: {
                            Text(emoji)
                        }
                    }
                } label: {
                    Label(loc("chat.react"), systemImage: "face.smiling")
                }

                Divider()

                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label(loc("post.copy"), systemImage: "doc.on.doc")
                }

                if let onDelete {
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(loc("chat.message.delete"), systemImage: "trash")
                    }
                }
            }

            if !isOutgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    /// A single reaction pill showing the emoji and count (if > 1).
    private func reactionPill(emoji: String, count: Int) -> some View {
        Button {
            onReactionTap?(emoji)
        } label: {
            HStack(spacing: 2) {
                Text(emoji)
                    .font(.caption2)
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
    }

    /// Converts @mentions in the text to tappable links with a custom mention:// scheme.
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

// MARK: - BubbleShape

/// Chat bubble shape with a tail on the bottom corner — tail position
/// flips based on whether the message is outgoing (right) or incoming (left).
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
