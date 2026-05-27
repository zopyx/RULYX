import Foundation

/// Manages push notification registration with the Bluesky AT Protocol.
/// Implementations handle registering and unregistering device tokens
/// for push notifications via the authenticated XRPC endpoint.
@MainActor
protocol BlueskyPushNotificationServicing {
    /// Registers a device token for push notifications with the given service.
    /// - Parameters:
    ///   - serviceDID: The DID of the push notification service.
    ///   - token: The device push token string.
    ///   - appID: The bundle identifier of the app.
    ///   - account: The account to register for push notifications.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
    func registerPush(
        serviceDID: String,
        token: String,
        appID: String,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Unregisters a device token, stopping push notifications for the given service.
    /// - Parameters:
    ///   - serviceDID: The DID of the push notification service.
    ///   - token: The device push token string to unregister.
    ///   - appID: The bundle identifier of the app.
    ///   - account: The account to unregister from push notifications.
    ///   - appPassword: The app password for authentication, or `nil` to use the cached session.
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
