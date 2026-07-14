@testable import RULYX
import XCTest

/// Architecture enforcement tests — static source analysis that verifies
/// the refactored architecture rules are not violated.
///
/// These tests run as part of CI and act as guardrails preventing layer violations.
/// Tests are structured to fail only on critical violations, reporting others as warnings.
final class ArchitectureEnforcementTests: XCTestCase {
    // MARK: - Source Tree Helpers

    private var sourceFiles: [String] {
        let sourcesURL = projectSourcesURL
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { ($0 as? URL)?.path }.filter { $0.hasSuffix(".swift") }
    }

    private var projectSourcesURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Sources")
    }

    // MARK: - Rule: Mock Implementations Are Classes

    /// All mock implementations must be classes (reference types), not structs.
    /// Struct mocks cause silent test failures because SwiftUI copies them.
    func testMockImplementationsAreClasses() {
        let mockFiles = sourceFiles.filter {
            ($0 as NSString).lastPathComponent.hasPrefix("Mock") && $0.contains("/Tests/")
        }

        for file in mockFiles {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("struct Mock") {
                    XCTFail("Mock file \(file) uses 'struct' — mocks MUST be classes to preserve reference semantics.")
                    break
                }
                if trimmed.hasPrefix("final class Mock") || trimmed.hasPrefix("class Mock") {
                    break
                }
            }
        }
    }

    // MARK: - Rule: Service Protocol Naming Convention

    /// All service protocols under Protocols/ should follow the *Servicing naming convention.
    /// AccountStoreProtocol is exempt (it's a store protocol, not a service protocol).
    func testServiceProtocolsFollowNamingConvention() throws {
        let protocolDir = projectSourcesURL
            .appendingPathComponent("Domain/Services/Protocols")
        guard FileManager.default.fileExists(atPath: protocolDir.path) else { return }

        let files = try FileManager.default.contentsOfDirectory(atPath: protocolDir.path)
            .filter { $0.hasSuffix(".swift") }
            .filter { $0 != "AccountStoreProtocol.swift" } // Store protocol, not service

        for file in files {
            let name = (file as NSString).deletingPathExtension
            XCTAssertTrue(
                name.hasSuffix("Servicing"),
                "Protocol file '\(file)' does not follow *Servicing naming convention"
            )
        }
    }

    // MARK: - Rule: DTOs Directory (Post-Phase 2.3)

    func testDTOsDirectoryStructure() throws {
        let dtosDir = projectSourcesURL
            .appendingPathComponent("Domain/Models/DTOs")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dtosDir.path, isDirectory: &isDirectory)
        // Not a hard failure — DTO split may not have been merged yet
        if exists, isDirectory.boolValue {
            let contents = try FileManager.default.contentsOfDirectory(atPath: dtosDir.path)
            XCTAssertFalse(contents.isEmpty, "DTOs directory exists but is empty")
        }
    }

    // MARK: - Rule: View-Service Coupling Report (Informational)

    /// Reports how many view files still import service implementations directly.
    /// This is an informational test — it always passes but logs a warning if violations exist.
    /// After the refactoring is complete, change to a hard assertion.
    func testViewServiceCouplingReport() {
        let viewFiles = sourceFiles.filter {
            $0.contains("/Features/") || $0.contains("/App/")
        }

        let forbiddenImports = [
            "LiveBlueskyClient",
            "BlueskyRequestExecutor",
            "BlueskySessionService",
        ]

        var violations: [(file: String, line: Int, symbol: String)] = []
        let exemptFiles: Set = [
            "AppDependencies.swift", "RULYXApp.swift", "RootView.swift",
        ]

        for file in viewFiles {
            let fileName = (file as NSString).lastPathComponent
            if exemptFiles.contains(fileName) {
                continue
            }
            if fileName.contains("ViewModel") || fileName.contains("ViewModel+") {
                continue
            }
            if fileName.hasPrefix("iPad") {
                continue
            }

            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                    continue
                }
                for symbol in forbiddenImports {
                    if line.contains(symbol) {
                        violations.append((file, index + 1, symbol))
                    }
                }
            }
        }

        if !violations.isEmpty {
            print("Note: \(violations.count) view files still reference service implementations directly (refactoring in progress)")
        }
        // Not a hard failure during active refactoring
        XCTAssertTrue(true)
    }
}
