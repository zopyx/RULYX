import SwiftUI

/// Shared floating action button for composing new posts on timelines.
///
/// Renders a `square.and.pencil` icon in a filled sky-blue circle.
/// Supports animated appear/disappear via `isVisible` and standard
/// bottom-trailing overlay positioning.
struct TimelineComposeFAB: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        if isVisible {
            Button(action: action) {
                Image(systemName: "square.and.pencil")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.skyPrimary))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .accessibilityLabel(loc("timeline.new_post"))
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview {
    VStack {
        Spacer()
        HStack {
            Spacer()
            TimelineComposeFAB(isVisible: true, action: {})
        }
    }
}
