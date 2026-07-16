import SwiftUI

/// A generated avatar for group conversations.
///
/// Displays member avatars in a stacked layout (up to 4 in a 2×2 grid),
/// with a +N badge when there are more than 4 members. Falls back to
/// initials of the group name or "G" when no avatars are available.
struct GroupAvatarView: View {
    let members: [ChatMemberProfile]
    let groupName: String
    let size: CGFloat

    private var displayMembers: [ChatMemberProfile] {
        Array(members.prefix(4))
    }

    private var excessCount: Int {
        max(0, members.count - 4)
    }

    private var initials: String {
        let name = groupName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "G" }
        let parts = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let second = parts[1].prefix(1).uppercased()
            return first + second
        }
        return String(name.prefix(2)).uppercased()
    }

    private var hasAvatars: Bool {
        members.contains { $0.avatarURL != nil }
    }

    var body: some View {
        if hasAvatars {
            avatarGrid
        } else {
            fallbackAvatar
        }
    }

    // MARK: - Avatar grid

    private var avatarGrid: some View {
        ZStack {
            switch displayMembers.count {
            case 1:
                memberAvatar(displayMembers[0], at: 0)
            case 2:
                HStack(spacing: 2) {
                    memberAvatar(displayMembers[0], at: 0)
                    memberAvatar(displayMembers[1], at: 1)
                }
            case 3, 4:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        memberAvatar(displayMembers[safe: 0], at: 0)
                        memberAvatar(displayMembers[safe: 1], at: 1)
                    }
                    HStack(spacing: 2) {
                        memberAvatar(displayMembers[safe: 2], at: 2)
                        if displayMembers.count == 4 {
                            memberAvatar(displayMembers[3], at: 3)
                        } else if excessCount > 0 {
                            excessBadge
                        }
                    }
                }
            default:
                fallbackAvatar
            }

            if excessCount > 0, displayMembers.count < 4 {
                // Badge is handled inside the grid for 3-member case
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func memberAvatar(_ member: ChatMemberProfile?, at _: Int) -> some View {
        if let member, let url = member.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    initialAvatar(member.displayName ?? member.handle)
                }
            }
        } else if let member {
            initialAvatar(member.displayName ?? member.handle)
        } else {
            Color.clear
        }
    }

    private var excessBadge: some View {
        ZStack {
            Color.skyPrimary
            Text("+\(excessCount)")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Fallback

    private var fallbackAvatar: some View {
        Circle()
            .fill(Color.skyPrimary.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color.skyPrimary)
            }
    }

    private func initialAvatar(_ name: String) -> some View {
        ZStack {
            Color.skyPrimary.opacity(0.2)
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(Color.skyPrimary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        GroupAvatarView(members: [], groupName: "Team Alpha", size: 48)
        GroupAvatarView(
            members: [ChatMemberProfile(did: "1", handle: "alice", displayName: "Alice", avatarURL: nil)],
            groupName: "Chat", size: 48
        )
    }
    .padding()
}
