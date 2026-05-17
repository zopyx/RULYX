import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var appLockManager: AppLockManager
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("showBetaFeatures") private var showBetaFeatures = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var isShowingClearCacheConfirmation = false
    @State private var cacheStatusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(
                        selection: Binding(
                            get: { self.appearanceMode },
                            set: { self.appearanceMode = $0 }
                        )
                    ) {
                        Text(loc("settings.appearance.light")).tag("light")
                        Text(loc("settings.appearance.system")).tag("system")
                        Text(loc("settings.appearance.dark")).tag("dark")
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
                    .accessibilityHint(loc("settings.language.hint"))
                } header: {
                        Text(localizationManager.localized("settings.preferences"))
                    }

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
                            Picker(loc("settings.auto_lock"), selection: $appLockManager.timeoutMinutes) {
                                Text(loc("settings.auto_lock.immediately")).tag(0)
                                Text(loc("settings.auto_lock.1min")).tag(1)
                                Text(loc("settings.auto_lock.5min")).tag(5)
                                Text(loc("settings.auto_lock.15min")).tag(15)
                                Text(loc("settings.auto_lock.30min")).tag(30)
                            }
                        }
                    } header: {
                        Text(loc("settings.security"))
                    } footer: {
                        if appLockManager.isEnabled {
                            Text(loc("settings.biometric_footer").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel))
                        }
                    }
                }

                Section {
                    ForEach(GIFProvider.allCases) { provider in
                        let key = Binding(
                            get: { UserDefaults.standard.string(forKey: provider.apiKeyUserDefaultsKey) ?? "" },
                            set: { UserDefaults.standard.set($0.isEmpty ? nil : $0, forKey: provider.apiKeyUserDefaultsKey) }
                        )
                        SecureField(loc("settings.gif_api_key").replacingOccurrences(of: "{provider}", with: provider.rawValue), text: key)
                    }
                } header: {
                    Text(verbatim: loc("settings.gif_services"))
                } footer: {
                    Text(verbatim: loc("settings.gif_services_desc"))
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
                    .accessibilityHint(loc("settings.debug_tools.hint"))

                    Button(role: .destructive) {
                        isShowingClearCacheConfirmation = true
                    } label: {
                        Label {
                            Text(localizationManager.localized("settings.clear_cache"))
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .accessibilityHint(loc("settings.clear_cache.hint"))

                    if let cacheStatusMessage {
                        Text(cacheStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(localizationManager.localized("settings.internal"))
                }
            }
            .navigationTitle(localizationManager.localized("settings.title"))
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

    private var biometricIcon: String {
        switch appLockManager.biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }
}

#Preview {
    SettingsView()
}
