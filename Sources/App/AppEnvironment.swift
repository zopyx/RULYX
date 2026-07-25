import Foundation

/// Consolidated wrapper for low-frequency app-level stores and services.
/// Injected as a single @EnvironmentObject to reduce the fan-out of 14
/// individual injections at the RULYXApp root.
///
/// Migration: replace `@EnvironmentObject var mutedWordsStore: MutedWordsStore`
/// with `@EnvironmentObject var env: AppEnvironment` and access via
/// `env.mutedWordsStore`.
@MainActor
final class AppEnvironment: ObservableObject {
    let mutedWordsStore: MutedWordsStore
    let analyticsStore: AnalyticsStore
    let internalListStore: InternalListStore
    let httpRequestDebugStore: HTTPRequestDebugStore
    let clearskyHeartbeat: ClearskyHeartbeatService
    let autoBlockBackService: AutoBlockBackService
    let aiService: LiveAIService
    let chatStore: ChatStore

    init(
        mutedWordsStore: MutedWordsStore,
        analyticsStore: AnalyticsStore,
        internalListStore: InternalListStore,
        httpRequestDebugStore: HTTPRequestDebugStore,
        clearskyHeartbeat: ClearskyHeartbeatService,
        autoBlockBackService: AutoBlockBackService,
        aiService: LiveAIService,
        chatStore: ChatStore
    ) {
        self.mutedWordsStore = mutedWordsStore
        self.analyticsStore = analyticsStore
        self.internalListStore = internalListStore
        self.httpRequestDebugStore = httpRequestDebugStore
        self.clearskyHeartbeat = clearskyHeartbeat
        self.autoBlockBackService = autoBlockBackService
        self.aiService = aiService
        self.chatStore = chatStore
    }
}
