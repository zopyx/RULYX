import SwiftUI

// MARK: - Floating Glass Toolbar

/// A floating, Liquid Glass toolbar whose items slide horizontally.
///
/// Rendering: the bar uses the iOS 26 Liquid Glass material (`glassEffect`) and degrades to
/// `.thinMaterial` on iOS 17–25 through `glassBackground(in:)`.
///
/// Layout: the slot width is derived from the available width, so the slots always fill the bar
/// when they fit. When they cannot fit — narrow devices or a longer item list — the row scrolls
/// horizontally instead of shrinking past `minItemWidth`. Whenever `selectedID` changes the
/// matching slot is scrolled back into view (centred).
///
/// Usage: `content` receives the resolved slot width and must apply it to every slot. Give each
/// slot an `.id(_:)` equal to the value the selection is tracked by, so scrolling can find it.
struct FloatingGlassToolbar<Content: View>: View {
    /// Total number of slots in the row, including any accessory the caller adds.
    let itemCount: Int
    /// Slots are never narrower than this — the row scrolls instead.
    var minItemWidth: CGFloat = 40
    /// Slots are never wider than this — surplus width stays as bar padding.
    var maxItemWidth: CGFloat = 88
    /// Spacing between slots.
    var slotSpacing: CGFloat = 1
    /// Padding between the bar edge and the first/last slot.
    var edgePadding: CGFloat = 5
    /// Height of the bar.
    var height: CGFloat = 58
    /// Identifier of the currently selected slot; scrolled into view when it changes.
    var selectedID: String?
    /// Builds the row content, applying the resolved slot width to each slot.
    @ViewBuilder let content: (CGFloat) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bar grows with Dynamic Type: at accessibility sizes the caller drops the captions
    /// (icon-only slots), so the height is what has to carry the text-size signal.
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 58

    /// The row is laid out a hair narrower than the bar so that rounding can never push the
    /// last slot past the scroll view's bounds — SwiftUI drops clipped slots from the
    /// accessibility tree, which makes them untappable for VoiceOver and UI tests.
    private static var overflowGuard: CGFloat {
        2
    }

    var body: some View {
        GeometryReader { proxy in
            let slots = CGFloat(max(itemCount, 1))
            let spacing = slotSpacing * CGFloat(max(itemCount - 1, 0))
            let available = max(0, proxy.size.width - edgePadding * 2 - spacing - Self.overflowGuard)
            let itemWidth = min(maxItemWidth, max(minItemWidth, available / slots))

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: slotSpacing) {
                        content(itemWidth)
                    }
                    .padding(.horizontal, edgePadding)
                }
                .scrollIndicators(.hidden)
                // The bar's silhouette is the capsule drawn behind it; without clipping, a slot
                // near either curved end (the selection pill) pokes out of the capsule.
                .clipShape(Capsule())
                // Only bounce when the row actually overflows, so a fitting bar stays still.
                .scrollBounceBehavior(.basedOnSize)
                // Restores the selected slot on appear (a restored session can start on a tab
                // that sits outside the visible row) and follows later selection changes.
                .onAppear { scrollSelected(into: scrollProxy) }
                .onChange(of: selectedID) { _, _ in
                    scrollSelected(into: scrollProxy)
                }
            }
        }
        .frame(height: max(height, scaledHeight))
        .glassBackground(in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    /// Scrolls the slot whose `id` matches `selectedID` to the centre of the bar. Honours
    /// Reduce Motion: the slot still comes into view, it just does not slide there.
    private func scrollSelected(into proxy: ScrollViewProxy) {
        guard let selectedID else { return }
        if reduceMotion {
            proxy.scrollTo(selectedID, anchor: .center)
        } else {
            withAnimation(.snappy(duration: 0.28)) {
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
    }
}
