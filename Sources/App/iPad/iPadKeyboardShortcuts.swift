import SwiftUI

@MainActor
final class iPadKeyboardShortcuts: ObservableObject {
    @Published var isCommandPalettePresented = false

    static let shared = iPadKeyboardShortcuts()
}
