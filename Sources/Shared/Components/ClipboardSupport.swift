import CoreTransferable
import SwiftUI

// MARK: - Clipboard Support (iOS 27)

extension View {
    /// Marks the view as a copy source for the system clipboard on iOS 27 — the payload becomes
    /// available in the standard Copy menu and to other apps. No-op before iOS 27.
    @ViewBuilder
    func appCopyable(_ payload: @autoclosure @escaping () -> [some Transferable]) -> some View {
        if #available(iOS 27.0, *) {
            copyable(payload())
        } else {
            self
        }
    }

    /// Accepts a paste of the given transferable type on iOS 27. No-op before iOS 27, where the
    /// same data can still arrive through the drag & drop paths in `iPadDragDrop`.
    @ViewBuilder
    func appPasteDestination<T: Transferable>(
        for payloadType: T.Type = T.self,
        action: @escaping ([T]) -> Void
    ) -> some View {
        if #available(iOS 27.0, *) {
            pasteDestination(for: payloadType, action: action)
        } else {
            self
        }
    }
}
