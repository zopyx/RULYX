import Foundation

// MARK: - CSV String Helpers

extension String {
    /// Returns the string escaped as a CSV field (double-quoted, internal quotes doubled).
    var csvField: String {
        let escaped = replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
