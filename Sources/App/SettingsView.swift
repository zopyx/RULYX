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

    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var appLockManager: AppLockManager
    @EnvironmentObject private var httpRequestDebugStore: HTTPRequestDebugStore
    @EnvironmentObject private var aiService: LiveAIService
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var internalListStore: InternalListStore
    @EnvironmentObject private var moderationAuditStore: ModerationAuditStore
    @EnvironmentObject private var crashReportingManager: CrashReportingManager

    /// UserDefaults key `"debugMode"`: enables debug tools (HTTP request debug view, etc.).
    @AppStorage("debugMode") private var debugMode = false

    /// UserDefaults key `"autoBlockBackEnabled"`: automatically blocks back accounts that block the user.
    @AppStorage("autoBlockBackEnabled") private var autoBlockBackEnabled = true

    /// UserDefaults key `"autoBlockBackIntervalMinutes"`: how often to check for new blockers.
    /// 0 = never, 5/20/60/360/1440 minutes.
    @AppStorage("autoBlockBackIntervalMinutes") private var autoBlockBackInterval = 30

    /// UserDefaults key `"appearanceMode"`: the user's preferred color scheme.
    /// Values: `"light"`, `"dark"`, or `"system"`.
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    /// Controls the clear cache confirmation dialog.
    @State private var isShowingClearCacheConfirmation = false
    @State private var isShowingDeleteAllDataConfirmation = false

    /// Crash reporting toggle binding — syncs with CrashReportingManager.shared.
    private var crashReportingEnabled: Binding<Bool> {
        Binding(
            get: { crashReportingManager.isEnabled },
            set: { crashReportingManager.isEnabled = $0 }
        )
    }

    /// Controls the HTTP request debug view sheet.
    @State private var isShowingHTTPRequestDebugView = false

    /// UserDefaults key `"showDangerousOperations"`: destructive operations visibility.
    @AppStorage("showDangerousOperations") private var showDangerousOperations = false

    /// UserDefaults key `"confirmBlocks"`: show confirmation dialog before blocking.
    @AppStorage("confirmBlocks") private var confirmBlocks = true

    /// UserDefaults key `"confirmUnfollow"`: show confirmation dialog before unfollowing.
    @AppStorage("confirmUnfollow") private var confirmUnfollow = true

    /// When enabled, the performance monitor overlay is shown at the top of the screen.
    @AppStorage("performanceOverlayEnabled") private var performanceOverlayEnabled = false

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
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    Toggle(isOn: $autoBlockBackEnabled) {
                        Label {
                            Text(loc("settings.autoblock"))
                        } icon: {
                            Image(systemName: "shield.checkered")
                        }
                    }
                    .accessibilityHint(loc("settings.autoblock.hint"))

                    if autoBlockBackEnabled {
                        Picker(selection: $autoBlockBackInterval) {
                            ForEach(AutoBlockBackService.Interval.allCases) { interval in
                                Text(loc(interval.labelKey))
                                    .tag(interval.rawValue)
                            }
                        } label: {
                            Label {
                                Text(loc("settings.autoblock.interval"))
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                    }

                    Toggle(isOn: $confirmBlocks) {
                        Label {
                            Text(loc("settings.confirm_blocks"))
                        } icon: {
                            Image(systemName: "hand.raised")
                        }
                    }

                    Toggle(isOn: $confirmUnfollow) {
                        Label {
                            Text(loc("settings.confirm_unfollow"))
                        } icon: {
                            Image(systemName: "person.badge.minus")
                        }
                    }

                    NavigationLink {
                        AutoBlockListPickerView()
                            .environmentObject(container)
                            .environmentObject(accountStore)
                            .environmentObject(internalListStore)
                            .environmentObject(localizationManager)
                    } label: {
                        Label {
                            Text(loc("settings.autoblock.lists"))
                        } icon: {
                            Image(systemName: "list.bullet.clipboard")
                        }
                    }
                } header: {
                    Text(loc("settings.moderation"))
                        .accessibilityAddTraits(.isHeader)
                } footer: {
                    Text(loc("settings.autoblock.footer"))
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
                            Picker(loc("settings.auto_lock"), selection: $appLockManager.timeoutMinutes) {
                                Text(loc: "settings.auto_lock.immediately").tag(0)
                                Text(loc: "settings.auto_lock.1min").tag(1)
                                Text(loc: "settings.auto_lock.5min").tag(5)
                                Text(loc: "settings.auto_lock.15min").tag(15)
                                Text(loc: "settings.auto_lock.30min").tag(30)
                            }
                        }
                    } header: {
                        Text(loc: "settings.security")
                            .accessibilityAddTraits(.isHeader)
                    } footer: {
                        if appLockManager.isEnabled {
                            Text(loc("settings.biometric_footer").replacingOccurrences(of: "{biometric}", with: appLockManager.biometricLabel))
                        }
                    }

                    // Crash Reporting (MetricKit)
                    Toggle(isOn: crashReportingEnabled) {
                        Label {
                            Text(loc("settings.crash_reporting"))
                        } icon: {
                            Image(systemName: "ant.circle")
                        }
                    }
                    .accessibilityHint(loc: "settings.crash_reporting.hint")
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
                                Image(systemName: "brain.head.profile")
                            }
                        }
                    } header: {
                        Text(localizationManager.localized("settings.ai"))
                            .accessibilityAddTraits(.isHeader)
                    }

                    // MARK: About Section — prominent info link

                    Section {
                        NavigationLink {
                            InfoView()
                                .environmentObject(localizationManager)
                        } label: {
                            Label {
                                Text(localizationManager.localized("tab.info"))
                                    .fontWeight(.medium)
                            } icon: {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Color.skyPrimary)
                            }
                        }
                    } header: {
                        Text(localizationManager.localized("settings.about"))
                            .accessibilityAddTraits(.isHeader)
                    }

                    // MARK: Internal Section

                Section {
                    Toggle(isOn: $debugMode) {
                        Label {
                            Text(localizationManager.localized("settings.debug"))
                        } icon: {
                            Image(systemName: "wrench.adjustable")
                        }
                    }
                    .accessibilityHint(loc: "settings.debug_tools.hint")

                    if debugMode {
                        Toggle(isOn: $performanceOverlayEnabled) {
                            Label {
                                Text("Performance Overlay")
                            } icon: {
                                Image(systemName: "chart.bar.fill")
                            }
                        }

                        Toggle(isOn: $showDangerousOperations) {
                            Label {
                                Text(localizationManager.localized("settings.dangerous_operations"))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                        }
                        .accessibilityHint(loc: "settings.dangerous_operations.hint")

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

                    if debugMode {
                        Button(role: .destructive) {
                            isShowingDeleteAllDataConfirmation = true
                        } label: {
                            Label {
                                Text(loc: "settings.delete_all_data")
                            } icon: {
                                Image(systemName: "trash.fill")
                            }
                        }
                        .accessibilityHint(loc: "settings.delete_all_data.hint")
                    }

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
                    .accessibilityAddTraits(.isHeader)
                    .contentShape(Rectangle())
                    // Hidden gesture: double-tapping the "Internal" section header
                    // opens the HTTP request debug view — gated behind `debugMode`
                    // so the 24h request log (handles, search queries) is not
                    // reachable on a casual user's device.
                    .onTapGesture(count: 2) {
                        guard debugMode else { return }
                        isShowingHTTPRequestDebugView = true
                    }
                }
            }
            .pageTitle(localizationManager.localized("settings.title"))

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
                    container.auth.clearCache()
                    cacheStatusMessage = loc("settings.cache_cleared")
                }
                Button(localizationManager.localized("settings.cancel"), role: .cancel) {}
            } message: {
                Text(localizationManager.localized("settings.clear_cache.message"))
            }

            // MARK: Confirmation — Delete All Data

            .confirmationDialog(
                loc("settings.delete_all_data.confirm"),
                isPresented: $isShowingDeleteAllDataConfirmation,
                titleVisibility: .visible
            ) {
                Button(loc("settings.delete_all_data"), role: .destructive) {
                    moderationAuditStore.clearAll()
                    container.auth.clearCache()
                    DashboardCache.clearAll()
                    RelationshipCache.clearAll()
                    cacheStatusMessage = loc("settings.data_deleted")
                }
                Button(localizationManager.localized("settings.cancel"), role: .cancel) {}
            } message: {
                Text(loc("settings.delete_all_data.message"))
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
        .environmentObject(LiveAIService())
        .environmentObject(AccountStore(preview: true))
        .environmentObject(InternalListStore())
}
