import Foundation

@MainActor
protocol BlueskyPushNotificationServicing {
    func registerPush(
        serviceDID: String,
        token: String,
        appID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws
    func unregisterPush(
        serviceDID: String,
        token: String,
        appID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws
}

@MainActor
final class BlueskyPushNotificationService: BlueskyPushNotificationServicing {
    private let requestExecutor: BlueskyRequestExecuting
    private let sessionService: BlueskySessionServicing

    init(requestExecutor: BlueskyRequestExecuting, sessionService: BlueskySessionServicing) {
        self.requestExecutor = requestExecutor
        self.sessionService = sessionService
    }

    func registerPush(
        serviceDID: String,
        token: String,
        appID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let body = RegisterPushRequest(
            serviceDid: serviceDID,
            token: token,
            platform: "ios",
            appId: appID
        )

        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { session in
            try await self.requestExecutor.send(
                path: "app.bsky.notification.registerPush",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: session.accessJWT,
                hostURL: session.pdsURL
            )
        }
    }

    func unregisterPush(
        serviceDID: String,
        token: String,
        appID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws {
        let body = UnregisterPushRequest(
            serviceDid: serviceDID,
            token: token,
            platform: "ios",
            appId: appID
        )

        let _: EmptyResponse = try await sessionService.performAuthenticatedRequest(account: account, appPassword: appPassword) { session in
            try await self.requestExecutor.send(
                path: "app.bsky.notification.unregisterPush",
                method: "POST",
                queryItems: [],
                body: body,
                accessToken: session.accessJWT,
                hostURL: session.pdsURL
            )
        }
    }
}

private struct RegisterPushRequest: Encodable {
    let serviceDid: String
    let token: String
    let platform: String
    let appId: String
}

private struct UnregisterPushRequest: Encodable {
    let serviceDid: String
    let token: String
    let platform: String
    let appId: String
}
