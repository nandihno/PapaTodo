import Foundation
import Supabase

/// APNs device registration through the `register_notification_device` / `unregister_notification_device`
/// database functions. Both run as the signed-in user and reject anyone else, so the token is always
/// filed under the caller.
nonisolated struct SupabaseNotificationDeviceRegistry: NotificationDeviceRegistering {
    let client: SupabaseClient
    let environment: AppConfiguration.APNsEnvironment
    let bundleIdentifier: String

    private struct Params: Encodable {
        let p_device_token: String
        let p_apns_environment: String
        let p_app_bundle_id: String
    }

    func register(deviceToken: String) async throws {
        try await call("register_notification_device", deviceToken: deviceToken)
    }

    func unregister(deviceToken: String) async throws {
        try await call("unregister_notification_device", deviceToken: deviceToken)
    }

    private func call(_ function: String, deviceToken: String) async throws {
        do {
            _ = try await client.rpc(
                function,
                params: Params(
                    p_device_token: deviceToken,
                    p_apns_environment: environment.rawValue,
                    p_app_bundle_id: bundleIdentifier
                )
            ).execute()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}

/// Calls the `send-push` Edge Function with the same event names and body the web app sends. The
/// server works out the recipients from the chore and the caller's identity, so nothing about who to
/// notify is sent from here.
nonisolated struct SupabaseNotificationDispatcher: NotificationDispatching {
    let client: SupabaseClient

    private struct Body: Encodable {
        let eventType: String
        let choreId: String
    }

    func notify(_ event: PushEvent, choreID: UUID) async {
        do {
            try await client.functions.invoke(
                "send-push",
                options: FunctionInvokeOptions(body: Body(eventType: event.rawValue, choreId: choreID.uuidString.lowercased()))
            )
        } catch {
            // Deliberately swallowed: the chore change itself already succeeded.
        }
    }
}
