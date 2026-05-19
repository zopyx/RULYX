import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var appLockManager: AppLockManager
    @EnvironmentObject private var httpRequestDebugStore: HTTPRequestDebugStore
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("showBetaFeatures") private var showBetaFeatures = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var isShowingClearCacheConfirmation = false
    @State private var isShowingHTTPRequestDebugView = false
    @State private var cacheStatusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(
                        selection: Binding(
                            get: { appearanceMode },
                            set: { appearanceMode = $0 }
                        )
                    ) {
                        Text("settings.appearance.light").tag("light")
                        Text("settings.appearance.system").tag("system")
                        Text("settings.appearance.dark").tag("dark")
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
                    .accessibilityHint("settings.language.hint")
                } header: {
                    Text(localizationManager.localized("settings.preferences"))
                }

                if appLockManager.isBiometricsAvailable {
                    Section {
                        Toggle(isOn: $appLockManager.isEnabled) {
                            Label {
                                Text(String(localized: "settings.biometric_lock").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel))
                            } icon: {
                                Image(systemName: biometricIcon)
                            }
                        }

                        if appLockManager.isEnabled {
                            Picker("settings.auto_lock", selection: $appLockManager.timeoutMinutes) {
                                Text("settings.auto_lock.immediately").tag(0)
                                Text("settings.auto_lock.1min").tag(1)
                                Text("settings.auto_lock.5min").tag(5)
                                Text("settings.auto_lock.15min").tag(15)
                                Text("settings.auto_lock.30min").tag(30)
                            }
                        }
                    } header: {
                        Text("settings.security")
                    } footer: {
                        if appLockManager.isEnabled {
                            Text(String(localized: "settings.biometric_footer").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel))
                        }
                    }
                }

                if showBetaFeatures {
                    Section {
                        let key = Binding(
                            get: { UserDefaults.standard.string(forKey: "klipyAPIKey") ?? "" },
                            set: { UserDefaults.standard.set($0.isEmpty ? nil : $0, forKey: "klipyAPIKey") }
                        )
                        SecureField("settings.klipy_api_key", text: key)
                    } header: {
                        Text("settings.klipy_services")
                    }
                }

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
                    .accessibilityHint("settings.debug_tools.hint")

                    Button(role: .destructive) {
                        isShowingClearCacheConfirmation = true
                    } label: {
                        Label {
                            Text(localizationManager.localized("settings.clear_cache"))
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .accessibilityHint("settings.clear_cache.hint")

                    if let cacheStatusMessage {
                        Text(cacheStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text(localizationManager.localized("settings.internal"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        isShowingHTTPRequestDebugView = true
                    }
                }
            }
            .navigationTitle(localizationManager.localized("settings.title"))
            .sheet(isPresented: $isShowingHTTPRequestDebugView) {
                NavigationStack {
                    HTTPRequestDebugView()
                        .environmentObject(httpRequestDebugStore)
                        .environmentObject(localizationManager)
                }
            }
            .confirmationDialog(
                localizationManager.localized("settings.clear_cache.confirm"),
                isPresented: $isShowingClearCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button(localizationManager.localized("settings.clear_cache"), role: .destructive) {
                    blueskyClient.clearCache()
                    cacheStatusMessage = String(localized: "settings.cache_cleared")
                }
                Button(localizationManager.localized("settings.cancel"), role: .cancel) {}
            } message: {
                Text(localizationManager.localized("settings.clear_cache.message"))
            }
        }
    }

    private var biometricIcon: String {
        switch appLockManager.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock.shield"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(LocalizationManager.shared)
        .environmentObject(AppLockManager.shared)
        .environmentObject(HTTPRequestDebugStore.shared)
}
