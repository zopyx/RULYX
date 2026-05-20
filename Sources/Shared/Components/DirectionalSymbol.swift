import SwiftUI

extension Image {
    /// Mark a directional SF Symbol so SwiftUI flips it under right-to-left layout.
    /// Use for disclosure chevrons, "forward" arrows, and other glyphs whose meaning is "in the reading direction".
    func directional() -> some View {
        flipsForRightToLeftLayoutDirection(true)
    }
}
