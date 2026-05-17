import SwiftUI

struct ImagePreviewCollection: Identifiable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
}

struct ImageCarouselView: View {
    let urls: [URL]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    init(urls: [URL], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.urls = urls
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    private var dragProgress: CGFloat {
        min(1, abs(dragOffset.height) / 200)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - dragProgress * 0.4)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    ZoomableImageView(url: url)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset.height)
            .scaleEffect(max(0.85, 1 - dragProgress * 0.15), anchor: .center)

            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(currentIndex + 1) / \(urls.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.4), in: Capsule())
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(8)
                            .background(.black.opacity(0.3), in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .opacity(1 - dragProgress)
                Spacer()
            }
        }
        .ignoresSafeArea()
        .gesture(
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.width) < abs(value.translation.height) * 0.5 {
                        isDragging = true
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    guard isDragging else { return }
                    isDragging = false
                    if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height - value.translation.height) > 400 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = CGSize(width: 0, height: value.translation.height > 0 ? 600 : -600)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onDismiss() }
                    } else {
                        withAnimation(.interactiveSpring) { dragOffset = .zero }
                    }
                }
        )
    }
}

struct ZoomableImageView: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, lastScale * value)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring) {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                            lastScale = 1
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
                .overlay {
                    if scale > 1 {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(panGesture)
                    }
                }
        } placeholder: {
            ProgressView()
                .tint(.white)
        }
    }
}
