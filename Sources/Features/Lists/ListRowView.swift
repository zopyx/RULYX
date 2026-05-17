import SwiftUI

struct ListRowView: View {
    let list: BlueskyList
    @ScaledMetric(relativeTo: .body) private var iconSize = 32

    var body: some View {
        HStack(spacing: 12) {
            if let avatarURL = list.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    listIcon
                }
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator, lineWidth: 0.5)
                }
            } else {
                listIcon
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text(list.description)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            if let memberCount = list.memberCount {
                Text("\(memberCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .appScrollTransition()
    }

    private var listIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(list.kind == .moderation ? Color.skyOrange.opacity(0.16) : Color.skyPrimary.opacity(0.14))
                .frame(width: iconSize, height: iconSize)
            Image(systemName: list.kind.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(list.kind == .moderation ? Color.skyOrange : Color.skyPrimary)
        }
    }
}

#Preview {
    List {
        ListRowView(
            list: BlueskyList(
                id: "preview",
                name: "Trusted Sources",
                description: "Accounts curated for signal over noise.",
                memberCount: 67,
                kind: .regular
            )
        )
    }
}
