import Foundation
import UIKit

/// Detects whether the current device is jailbroken by checking for common
/// indicators: known jailbreak files, writable system paths, and suspicious URL schemes.
enum JailbreakDetector {
    /// Returns `true` if the device shows signs of being jailbroken.
    /// Always returns `false` in the simulator.
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            return hasJailbreakFiles() || canWriteToSystemPaths() || canOpenJailbreakURLSchemes()
        #endif
    }

    // MARK: - Private Checks

    /// Known paths that indicate a jailbroken device.
    private static func hasJailbreakFiles() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/Applications/Sileo.app",
            "/private/var/lib/cydia",
            "/private/var/tmp/cydia.log",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    /// Attempts to write to a system path that should be read-only on stock iOS.
    private static func canWriteToSystemPaths() -> Bool {
        let testPath = "/private/jailbreak_test"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    /// Checks whether known jailbreak-related URL schemes can be opened.
    private static func canOpenJailbreakURLSchemes() -> Bool {
        let schemes = ["cydia://", "sileo://", "zbra://"]
        for scheme in schemes {
            guard let url = URL(string: scheme) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        return false
    }
}
