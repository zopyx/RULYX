import SwiftUI

// MARK: - ListRowView

/// A single row showing a list name, description, and member count.
struct ListRowView: View {
    /// The list to display.
    let list: BlueskyList

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
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
