import SwiftUI

// MARK: - SkeletonRow

/// A placeholder row matching the layout of `BlueskyActorRow` — circle + two text lines.
/// Used as a shimmer/skeleton loading state while data is being fetched.
struct SkeletonRow: View {
    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.quaternary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 160, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 100, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - SkeletonCard

/// A card-shaped skeleton placeholder with circle avatar and two text bars.
struct SkeletonCard: View {
    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.quaternary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - SkeletonGrid

/// A 2-column grid of `SkeletonCard` placeholders.
struct SkeletonGrid: View {
    // MARK: - Body

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
            ForEach(0 ..< 4) { _ in
                SkeletonCard()
            }
        }
    }
}

#Preview {
    List {
        SkeletonRow()
        SkeletonRow()
        SkeletonRow()
    }
    .listStyle(.insetGrouped)
}
