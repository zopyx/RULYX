import SwiftUI

extension View {
    func pageTitle(_ title: String) -> some View {
        navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
    }

    func pageTitle(_ title: Text) -> some View {
        navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
    }
}
