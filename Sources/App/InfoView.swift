import SwiftUI

// MARK: - Info View

/// The Info tab providing an overview of the app, feature descriptions, and legal information.
///
/// ## Tabs
/// - **Overview**: hero card with logo, claims grid (free, open-source, no tracking, no ads),
///   GitHub link, security note, and version/build info.
/// - **Features**: detailed breakdown of moderation, export, and list management features.
/// - **Legal**: author info, links to website/imprint/privacy, license, third-party services
///   (Clearsky), and data classification details.
///
/// ## Easter Eggs
/// - **Triple-tap** the logo → replays the splash screen animation.
/// - **Quadruple-tap** the logo → opens a hidden diagnostics view showing device info,
///   orientation, accessibility settings, and app version.
struct InfoView: View {
    // MARK: - Properties

    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.colorScheme) private var colorScheme

    /// The currently selected info tab (overview / features / legal).
    @State private var selectedTab: InfoTab = .overview

    /// Controls the splash screen replay overlay (triggered by triple-tapping the logo).
    @State private var showSplashReplay = false

    /// Controls the hidden debug diagnostics sheet (triggered by quadruple-tapping the logo).
    @State private var showDebugInfo = false

    /// The three segmented-picker tabs within the Info view.
    enum InfoTab: String, CaseIterable {
        case overview = "Overview"
        case features = "Features"
        case legal = "Legal"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // MARK: Background Gradient

            background
                .ignoresSafeArea()

            NavigationStack {
                VStack(spacing: 0) {
                    // MARK: Segmented Tab Picker

                    Picker(selection: $selectedTab) {
                        ForEach(InfoTab.allCases, id: \.self) { tab in
                            Text(verbatim: localizationManager.localized("info.\(tab.rawValue.lowercased())")).tag(tab)
                        }
                    } label: {
                        Text(verbatim: localizationManager.localized("info.section"))
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // MARK: Tab Content

                    ScrollView {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .overview: overviewTab
                            case .features: featuresTab
                            case .legal: legalTab
                            }
                        }
                        .padding(16)
                    }
                }
                // Suppresses the navigation bar title since the view provides its
                // own visual identity via the logo and background gradient.
                .navigationTitle("")
                .toolbarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }

        // MARK: Splash Replay Overlay

        .overlay {
            if showSplashReplay {
                SplashScreenView(isActive: $showSplashReplay)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }

        // MARK: Debug Info Sheet

        .sheet(isPresented: $showDebugInfo) {
            DebugInfoView()
                .environmentObject(localizationManager)
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(spacing: 16) {
            heroCard
            claimsGrid
            openSourceCard
            securityNote

            // MARK: Version / Build Row

            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: versionString)
                        .appFont(.subheading)
                        .foregroundStyle(.primary)
                    Text(buildDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Reads `CFBundleShortVersionString` and `CFBundleVersion` from Info.plist.
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    /// Reads the executable's modification date as a proxy for build date.
    /// Formatted as UTC via `SharedDateFormatters.buildTimestampUTC`.
    private var buildDate: String {
        if let url = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.modificationDate] as? Date
        {
            return SharedDateFormatters.buildTimestampUTC.string(from: date)
        }
        return "Unknown"
    }

    /// The hero card with the RULYX logo.
    /// - **Triple-tap** replays the splash screen.
    /// - **Quadruple-tap** opens the hidden debug diagnostics sheet.
    private var heroCard: some View {
        VStack(spacing: 10) {
            Image("RulyxLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 128)
                .onTapGesture(count: 3) { showSplashReplay = true }
                // Hidden easter egg: quadruple-tap opens debug diagnostics.
                // Uses `highPriorityGesture` to ensure it takes precedence over
                // the triple-tap gesture.
                .highPriorityGesture(TapGesture(count: 4).onEnded { showDebugInfo = true })

            Text(verbatim: localizationManager.localized("onboarding.title"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: heroGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    /// 2×2 grid of claim tiles: free, open-source, no tracking, no ads.
    private var claimsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            claimTile(icon: "dollarsign.circle.fill", text: localizationManager.localized("info.claim.free"), color: .skyPrimary)
            claimTile(icon: "swift", text: localizationManager.localized("info.claim.opensource"), color: .skyAccent)
            claimTile(icon: "hand.raised.slash.fill", text: localizationManager.localized("info.claim.notracking"), color: Color(red: 0.05, green: 0.70, blue: 0.60))
            claimTile(icon: "megaphone.slash.fill", text: localizationManager.localized("info.claim.noads"), color: .skyOrange)
        }
    }

    /// Card linking to the GitHub repository.
    private var openSourceCard: some View {
        Link(destination: URL(string: "https://github.com/zopyx/RULYX")!) {
            HStack(spacing: 14) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.title)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: localizationManager.localized("info.view_github"))
                        .appFont(.subheading)
                        .foregroundStyle(.primary)
                    Text(verbatim: localizationManager.localized("info.github_url"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .appFont(.label)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .tint(.primary)
        .accessibilityLabel(loc: "info.github.label")
        .accessibilityHint(loc: "info.github.hint")
    }

    /// Note explaining that credentials are stored in the Keychain, not UserDefaults.
    private var securityNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title)
                .foregroundStyle(Color.skyPrimary)
                .frame(width: 40, height: 40)
                .background(Color.skyPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: localizationManager.localized("info.keychain.title"))
                    .appFont(.subheading)
                    .foregroundStyle(.primary)
                Text(verbatim: localizationManager.localized("info.keychain.desc"))
                    .appFont(.label)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Features Tab

    /// Feature cards describing moderation lists, data export, and block management.
    private var featuresTab: some View {
        VStack(spacing: 12) {
            featureCard(
                icon: "checklist.checked",
                color: .skyPrimary,
                title: localizationManager.localized("info.feature.lists"),
                items: [
                    loc("info.feature.lists.browse"),
                    loc("info.feature.lists.bulk"),
                    loc("info.feature.lists.import"),
                    loc("info.feature.lists.export"),
                ]
            )

            featureCard(
                icon: "rectangle.split.3x1",
                color: .skyOrange,
                title: localizationManager.localized("info.feature.export"),
                items: [
                    loc("info.feature.export.posts"),
                    loc("info.feature.export.media"),
                    loc("info.feature.export.download"),
                ]
            )

            featureCard(
                icon: "hand.raised.square.on.square",
                color: .skyAccent,
                title: localizationManager.localized("info.feature.moderation"),
                items: [
                    loc("info.feature.moderation.block"),
                    loc("info.feature.moderation.block_all"),
                    loc("info.feature.moderation.membership"),
                ]
            )
        }
    }

    // MARK: - Legal Tab

    /// Legal info: author, website, imprint, privacy, license, third-party
    /// services (Clearsky), and data classification.
    private var legalTab: some View {
        VStack(spacing: 12) {
            legalRow(icon: "person.crop.square", title: localizationManager.localized("info.legal.author"), value: "Andreas Jung")

            Link(destination: URL(string: "https://www.py-consultant.com/")!) {
                legalRow(icon: "globe", title: localizationManager.localized("info.legal.website"), value: "py-consultant.com", link: true)
            }
            .tint(.primary)
            .accessibilityLabel(loc: "info.website.label")
            .accessibilityHint(loc: "info.website.hint")

            Link(destination: URL(string: "https://www.py-consultant.com/imprint-privacy.html")!) {
                legalRow(icon: "doc.text", title: localizationManager.localized("info.legal.imprint"), link: true)
            }
            .tint(.primary)
            .accessibilityLabel(loc: "info.imprint.label")
            .accessibilityHint(loc: "info.imprint.hint")

            Link(destination: URL(string: "https://www.py-consultant.com/imprint-privacy.html")!) {
                legalRow(icon: "hand.raised", title: localizationManager.localized("info.legal.privacy"), link: true)
            }
            .tint(.primary)
            .accessibilityLabel(loc: "info.privacy.label")
            .accessibilityHint(loc: "info.privacy.hint")

            legalRow(icon: "doc.text.magnifyingglass", title: localizationManager.localized("info.legal.license"), value: localizationManager.localized("info.legal.license_value"))

            Link(destination: URL(string: "https://github.com/zopyx/RULYX")!) {
                legalRow(icon: "chevron.left.forwardslash.chevron.right", title: localizationManager.localized("info.view_github"), value: "github.com/zopyx/RULYX", link: true)
            }
            .tint(.primary)
            .accessibilityLabel(loc: "info.github.label")
            .accessibilityHint(loc: "info.github.hint")

            legalDivider

            // MARK: Third-Party Services

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: localizationManager.localized("info.third_party"))
                    .appFont(.subheading)
                    .foregroundStyle(.primary)

                Link(destination: URL(string: "https://clearsky.app")!) {
                    legalRow(icon: "cloud", title: localizationManager.localized("info.legal.clearsky"), value: "clearsky.app", link: true)
                }
                .tint(.primary)
                .accessibilityLabel(loc: "info.clearsky.label")
                .accessibilityHint(loc: "info.clearsky.hint")

                Link(destination: URL(string: "https://github.com/ClearskyApp06/clearskyservices")!) {
                    legalRow(icon: "chevron.left.forwardslash.chevron.right", title: localizationManager.localized("info.legal.clearsky_github"), value: "github.com/ClearskyApp06", link: true)
                }
                .tint(.primary)
                .accessibilityLabel(loc: "info.clearsky_github.label")
                .accessibilityHint(loc: "info.clearsky_github.hint")

                Text(verbatim: localizationManager.localized("info.clearsky.desc"))
                    .appFont(.label)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 50)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            legalDivider

            // MARK: Data Classification

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: localizationManager.localized("info.data_classification"))
                    .appFont(.subheading)
                    .foregroundStyle(.primary)

                dataRow(label: localizationManager.localized("info.data.account"), value: localizationManager.localized("info.data.account_value"))
                dataRow(label: localizationManager.localized("info.data.api"), value: localizationManager.localized("info.data.api_value"))
                dataRow(label: localizationManager.localized("info.data.audit"), value: localizationManager.localized("info.data.audit_value"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Reusable Components

    /// A single tile in the 2×2 claims grid (free, open-source, no tracking, no ads).
    private func claimTile(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
            Text(text)
                .appFont(.subheading)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// A feature card with a title and bullet-pointed list of capabilities.
    private func featureCard(icon: String, color: Color, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(item)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// A row in the legal tab: icon, title, optional value, and optional external-link arrow.
    private func legalRow(icon: String, title: String, value: String? = nil, link: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.skyAccent)
                .frame(width: 36, height: 36)
                .background(Color.skyAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.subheading)
                    .foregroundStyle(.primary)
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if link {
                Image(systemName: "arrow.up.right")
                    .appFont(.label)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// A thin horizontal divider used to separate sections within the legal tab.
    private var legalDivider: some View {
        Color.appDivider.opacity(colorScheme == .dark ? 0.6 : 0.35)
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    /// A label + value row used in the data classification section.
    private func dataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appFont(.subheading)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Background

    /// Full-screen background gradient with decorative blurred circles.
    /// Uses different colors for light and dark mode.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.skyPrimary.opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 44)
                .offset(x: 140, y: -220)

            Circle()
                .fill(Color.skyAccent.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 54)
                .offset(x: -150, y: 240)
        }
        .ignoresSafeArea()
    }

    /// Gradient colors for the hero card, adapted for light/dark mode.
    private var heroGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.04, green: 0.20, blue: 0.50),
                Color(red: 0.05, green: 0.30, blue: 0.55),
                Color(red: 0.03, green: 0.45, blue: 0.42),
            ]
        }
        return [
            Color(red: 0.06, green: 0.36, blue: 0.80),
            Color(red: 0.08, green: 0.55, blue: 0.98),
            Color(red: 0.05, green: 0.77, blue: 0.73),
        ]
    }

    /// Gradient colors for the full-screen background, adapted for light/dark mode.
    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.04, green: 0.06, blue: 0.11),
                Color(red: 0.06, green: 0.09, blue: 0.16),
                Color(red: 0.04, green: 0.11, blue: 0.19),
            ]
        }

        return [
            Color(red: 0.95, green: 0.97, blue: 0.99),
            Color(red: 0.90, green: 0.95, blue: 0.99),
            Color(red: 0.93, green: 0.97, blue: 0.96),
        ]
    }
}

// MARK: - Debug Info View

/// Hidden diagnostics screen accessible by quadruple-tapping the RULYX logo
/// on the Info tab's overview section.
///
/// Displays device model, iOS version, screen dimensions, orientation, low-power
/// mode, thermal state, accessibility settings, and app version/build info.
private struct DebugInfoView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    /// Collected diagnostics tuples (label, value) populated on appear.
    @State private var diagnostics: [(String, String)] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(diagnostics.indices, id: \.self) { i in
                    let item = diagnostics[i]
                    LabeledContent(item.0, value: item.1)
                        .font(.caption.monospaced())
                }
            }
            .pageTitle(localizationManager.localized("debug.diagnostics"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Copies all diagnostics as tab-separated text to the clipboard.
                        let text = diagnostics.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            // Collects diagnostics on view appearance.
            .task { diagnostics = collectDiagnostics() }
        }
    }

    /// Gathers device, OS, accessibility, and app version information for diagnostics.
    private func collectDiagnostics() -> [(String, String)] {
        let device = UIDevice.current
        let screen = UIScreen.main
        let app = Bundle.main
        let process = ProcessInfo.processInfo

        var result: [(String, String)] = []
        let add = { (label: String, value: String) in result.append((label, value)) }

        add("Device Model", deviceModelName)
        add("Device Class", UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        add("iOS Version", "\(device.systemName) \(device.systemVersion)")
        add("Screen Size", "\(Int(screen.bounds.width))×\(Int(screen.bounds.height)) pt")
        add("Screen Scale", "\(Int(screen.scale))×")
        add("Screen Native", "\(Int(screen.nativeBounds.width))×\(Int(screen.nativeBounds.height)) px")
        add("Orientation", interfaceOrientation)
        add("Low Power Mode", process.isLowPowerModeEnabled ? "Yes" : "No")
        add("Thermal State", thermalState)
        add("App Language", localizationManager.currentLanguage)
        add("Device Language", Locale.current.language.languageCode?.identifier ?? "-")
        add("Region", Locale.current.region?.identifier ?? "-")
        add("Reduce Motion", UIAccessibility.isReduceMotionEnabled ? "Yes" : "No")
        add("Reduce Transparency", UIAccessibility.isReduceTransparencyEnabled ? "Yes" : "No")
        add("Bold Text", UIAccessibility.isBoldTextEnabled ? "Yes" : "No")
        add("Larger Text", UIAccessibility.isDarkerSystemColorsEnabled ? "Yes" : "No")
        add("Content Size", UIApplication.shared.preferredContentSizeCategory.rawValue)
        add("Total Disk", byteCount(process.physicalMemory))
        add("Thermal State", process.thermalState == .nominal ? "Nominal" : process.thermalState == .fair ? "Fair" : process.thermalState == .serious ? "Serious" : "Critical")
        add("Build Date", buildDate)
        let ver = app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let bld = app.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        add("Version", "v\(ver) (\(bld))")
        add("App Version", ver)
        add("App Build", bld)

        return result
    }

    /// Reads the device model via `sysctlbyname("hw.machine")`.
    private var deviceModelName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let data = Data(bytes: machine, count: machine.count)
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""
    }

    /// Returns a human-readable string for the current interface orientation.
    private var interfaceOrientation: String {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        switch scene?.interfaceOrientation {
        case .portrait: return "Portrait"
        case .landscapeLeft: return "Landscape Left"
        case .landscapeRight: return "Landscape Right"
        case .portraitUpsideDown: return "Portrait Upside Down"
        default: return "Unknown"
        }
    }

    /// Returns a human-readable string for the current thermal state.
    private var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    /// Reads the executable's modification date as a proxy for build date (UTC).
    private var buildDate: String {
        if let url = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.modificationDate] as? Date
        {
            return SharedDateFormatters.buildTimestampUTC.string(from: date)
        }
        return "Unknown"
    }

    /// Formats a byte count as a human-readable memory string.
    private func byteCount(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Preview

#Preview {
    InfoView()
}
