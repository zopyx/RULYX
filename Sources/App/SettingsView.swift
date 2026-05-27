import SwiftUI

// MARK: - Settings View

/// The Settings tab providing user-configurable preferences.
///
/// Sections:
/// - **Preferences**: appearance mode (light/dark/system) and language picker
/// - **Security**: biometric lock toggle and auto-lock timeout (only shown when
///   biometrics are available on the device)
/// - **AI**: navigation to AI model management
/// - **Internal**: beta features toggle, debug mode toggle, clear cache, and
///   a hidden HTTP request debug view (revealed by double-tapping the section header)
struct SettingsView: View {
    // MARK: - Properties

    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var appLockManager: AppLockManager
    @EnvironmentObject private var httpRequestDebugStore: HTTPRequestDebugStore
    @EnvironmentObject private var aiService: LiveAIService

    /// UserDefaults key `"debugMode"`: enables debug tools (HTTP request debug view, etc.).
    @AppStorage("debugMode") private var debugMode = false

    /// UserDefaults key `"showBetaFeatures"`: gates access to Timeline, Notifications,
    /// and Chat tabs in `RootView`.
    @AppStorage("showBetaFeatures") private var showBetaFeatures = false

    /// UserDefaults key `"appearanceMode"`: the user's preferred color scheme.
    /// Values: `"light"`, `"dark"`, or `"system"`.
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    /// Controls the clear cache confirmation dialog.
    @State private var isShowingClearCacheConfirmation = false

    /// Controls the HTTP request debug view sheet.
    @State private var isShowingHTTPRequestDebugView = false

    /// Transient status message shown after clearing the cache (e.g. "Cache cleared").
    @State private var cacheStatusMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // MARK: Preferences Section

                Section {
                    Picker(
                        selection: Binding(
                            get: { appearanceMode },
                            set: { appearanceMode = $0 }
                        )
                    ) {
                        Text(loc: "settings.appearance.light").tag("light")
                        Text(loc: "settings.appearance.system").tag("system")
                        Text(loc: "settings.appearance.dark").tag("dark")
                    } label: {
                        Label {
                            Text(localizationManager.localized("settings.appearance"))
                        } icon: {
                            Image(systemName: "moon.fill")
                        }
                    }

                    Picker(selection: Binding(
                        get: { localizationManager.currentLanguage },
                        set: { localizationManager.currentLanguage = $0 }
                    )) {
                        ForEach(localizationManager.supportedLanguages, id: \.code) { lang in
                            HStack {
                                Text(lang.displayName)
                                Spacer()
                                Text(lang.code.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(lang.code)
                        }
                    } label: {
                        Label {
                            Text(localizationManager.localized("settings.language"))
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                    .accessibilityHint(loc: "settings.language.hint")
                } header: {
                    Text(localizationManager.localized("settings.preferences"))
                }

                // MARK: Security Section (Biometrics)

                if appLockManager.isBiometricsAvailable {
                    Section {
                        Toggle(isOn: $appLockManager.isEnabled) {
                            Label {
                                Text(loc("settings.biometric_lock").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel))
                            } icon: {
                                Image(systemName: biometricIcon)
                            }
                        }

                        if appLockManager.isEnabled {
                            Picker("settings.auto_lock", selection: $appLockManager.timeoutMinutes) {
                                Text(loc: "settings.auto_lock.immediately").tag(0)
                                Text(loc: "settings.auto_lock.1min").tag(1)
                                Text(loc: "settings.auto_lock.5min").tag(5)
                                Text(loc: "settings.auto_lock.15min").tag(15)
                                Text(loc: "settings.auto_lock.30min").tag(30)
                            }
                        }
                    } header: {
                        Text(loc: "settings.security")
                    } footer: {
                        if appLockManager.isEnabled {
                            Text(loc("settings.biometric_footer").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel))
                        }
                    }
                }

                // MARK: AI Section

                Section {
                    NavigationLink {
                        AIModelManagementView()
                            .environmentObject(aiService)
                            .environmentObject(localizationManager)
                    } label: {
                        Label {
                            Text(localizationManager.localized("ai.models.title"))
                        } icon: {
                            Image(systemName: "brain")
                        }
                    }
                } header: {
                    Text(localizationManager.localized("settings.ai"))
                }

                // MARK: Internal Section

                Section {
                    Toggle(isOn: $showBetaFeatures) {
                        Label {
                            Text(localizationManager.localized("settings.beta_features"))
                        } icon: {
                            Image(systemName: "flask")
                        }
                    }

                    Toggle(isOn: $debugMode) {
                        Label {
                            Text(localizationManager.localized("settings.debug"))
                        } icon: {
                            Image(systemName: "wrench.adjustable")
                        }
                    }
                    .accessibilityHint(loc: "settings.debug_tools.hint")

                    Button(role: .destructive) {
                        isShowingClearCacheConfirmation = true
                    } label: {
                        Label {
                            Text(localizationManager.localized("settings.clear_cache"))
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .accessibilityHint(loc: "settings.clear_cache.hint")

                    if let cacheStatusMessage {
                        Text(cacheStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: HTTP Debug View (debug mode only)

                    if debugMode {
                        Button {
                            isShowingHTTPRequestDebugView = true
                        } label: {
                            Label {
                                Text(localizationManager.localized("debug.http.title"))
                            } icon: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(localizationManager.localized("settings.internal"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    // Hidden gesture: double-tapping the "Internal" section header
                    // opens the HTTP request debug view regardless of `debugMode`.
                    .onTapGesture(count: 2) {
                        isShowingHTTPRequestDebugView = true
                    }
                }
            }
            .navigationTitle(localizationManager.localized("settings.title"))

            // MARK: Sheet — HTTP Request Debug View

            .sheet(isPresented: $isShowingHTTPRequestDebugView) {
                NavigationStack {
                    HTTPRequestDebugView()
                        .environmentObject(httpRequestDebugStore)
                        .environmentObject(localizationManager)
                }
            }

            // MARK: Confirmation — Clear Cache

            .confirmationDialog(
                localizationManager.localized("settings.clear_cache.confirm"),
                isPresented: $isShowingClearCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button(localizationManager.localized("settings.clear_cache"), role: .destructive) {
                    blueskyClient.clearCache()
                    cacheStatusMessage = loc("settings.cache_cleared")
                }
                Button(localizationManager.localized("settings.cancel"), role: .cancel) {}
            } message: {
                Text(localizationManager.localized("settings.clear_cache.message"))
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns the SF Symbol name for the device's biometric type.
    /// - `.faceID` → `"faceid"`
    /// - `.touchID` → `"touchid"`
    /// - default → `"lock.shield"`
    private var biometricIcon: String {
        switch appLockManager.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock.shield"
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(LocalizationManager.shared)
        .environmentObject(AppLockManager.shared)
        .environmentObject(HTTPRequestDebugStore.shared)
}
