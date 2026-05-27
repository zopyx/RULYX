import SwiftUI

struct iPadEmptyDetailPlaceholder: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("iPad")
                    .font(.largeTitle.weight(.bold))
            } icon: {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.skyPrimary)
            }
        } description: {
            Text(loc("empty.select_item"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
