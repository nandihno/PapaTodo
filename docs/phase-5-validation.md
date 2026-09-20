# Phase 5 validation — Native APNs and shared notification delivery

Date: 2026-09-20
Plan: `docs/phase-5-plan.md` (approved by the user 2026-09-20).

**Status: Stage A (the native app) and Stage B (the backend code) are written, committed and tested locally. Stages C (secrets, migration, deploy) and D (device checks) have not started.** Nothing on the live backend has been changed for Phase 5, no secret has been set, the function has not been deployed, and no notification has been sent to anyone. The exit gate below is not met yet. Steps for the remaining work are in `docs/phase-5-deploy-runbook.md`.

## Stage A: what was built

- **Capability:** the Push Notifications capability and `aps-environment` entitlement (development; release builds use production) were added through Xcode, which accepted them for `org.nando.PapaTodos` on the paid team, and committed (`513a2b0`).
- **Permission and registration** (`PushRegistrationModel`, `SystemNotificationPermission`): the system prompt is only shown when the user asks (Home prompt or Settings). A device token (lowercase hex, the form the database requires) is held until someone is signed in, then registered with the backend's existing `register_notification_device` function using the build's APNs environment (sandbox for Debug, production for Release) and the bundle id. It is registered again on every sign-in and duplicate registrations of the same token are skipped. Tokens are never logged in full.
- **Sign-out** removes the device from the user first (`unregister_notification_device`) but only as a best effort with a three-second limit: a failing or hung call can never stop the user signing out.
- **UI:** a one-time "Get notified about your chores" prompt on Home (with Not Now, remembered across launches), and a Notifications section in Settings (permission state, Turn On Notifications, Open Settings when denied, whether this device is registered, and a retry).
- **Foreground presentation and taps** (`AppDelegate`, `PushBridge`): notifications that arrive while the app is open are shown as a banner and refresh the list. A tap opens the notification's chore (from its `choreId`). A tap that arrives before the app is ready (a cold launch) or before anyone is signed in is held and honored after sign-in; a chore that no longer exists shows "Chore not found".
- **Outbound notifications** (`NotificationDispatching`, `SupabaseNotificationDispatcher`): after a successful save, status change or comment the app asks the existing `send-push` function to notify the other people involved, with the same event names the web app uses. The server decides the recipients, so nothing about who to notify is sent from the phone. Rules: a new chore with an assignee sends `chore-assigned`; an edit that changed something sends `chore-updated` (an unchanged save sends nothing); a status change sends `status-changed`; a comment sends `comment-created`. These run in the background and can never delay or fail the action.
- Also fixed: a Swift 6 isolation warning from Phase 4 (`CalendarAccess`).

## Tests

- Full `xcodebuild test`, both targets: **TEST SUCCEEDED**. `PapaTodosTests`: **305 tests in 38 suites passed** (one skipped by design: the credentialed live read test). `PapaTodosUITests`: **37 tests, 0 failures**.
- New unit coverage: token hex encoding and redaction, the tap payload parser, the registration lifecycle (permission asked once, refused prompt, a token arriving before or after sign-in, re-registration on every sign-in, nothing registered without permission, failure and retry), sign-out (device removed, failure ignored, hung call never blocks), the Home prompt and its persistence, the cold-launch bridge, which saves and changes send which notification (and none when nothing changed or the action failed), a slow notifier never delaying an action, and live request shapes for device registration and `send-push`.
- New UI coverage: the Home prompt (turn on, Not Now), Settings in each permission state, turning notifications on from Settings, and a notification tap that arrives before sign-in opening the right chore (and "not found" for a missing one).
- Real Apple push delivery cannot be tested on the simulator here; that is Stage D on a device.

## Stage B: what was built (PapaBoard repo, commit `a58fd09`)

- **`send-push` delivers to iPhones as well as browsers.** New modules `apns.ts` (provider token signed from the `.p8` with ES256, HTTP/2 request to the sandbox or production host chosen per device, payload with the title and body plus `choreId` and `eventType` for tap routing, `apns-topic` from the bundle id, a collapse id per chore so newer notifications replace older ones, response classification) and `notifications.ts` (the who-is-told-what rules, extracted unchanged). `index.ts` runs Web Push and APNs at the same time and independently.
- **Off until configured.** APNs is used only if all four secrets exist (`APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`); without them the function behaves exactly as the deployed version does.
- **Recipient and de-duplication rules are unchanged** (creator and assignee minus the caller; assignment de-duplicated through `notification_deliveries`, shared by both channels) and pinned by tests.
- **Cleanup and diagnostics.** Only a device APNs says is gone (410, `BadDeviceToken`, `DeviceTokenNotForTopic`) is removed; expired or refused credentials, network errors, rate limits and our own request mistakes never remove a registration. An expired provider token is replaced once and the send retried. Logs carry counts and Apple's reason strings only, never device tokens, the key, or message text.
- **Migrations tracked in the repo:** `notification_devices` (already live; verified read-only against the file: same columns, constraints, four own-rows policies, two `security definer` functions with an empty search path), the `chore-images` DELETE policy (applied 2026-09-20), and a new, **unapplied** migration that revokes the two device functions from `anon`.
- **Tests:** `npm run test:functions` runs 30 tests under Node and they also pass under Deno (which found two things Node hid: a deterministic-signature assumption in my tests, and a type error that was already in the original function). They cover the provider token (its ES256 signature is verified against a generated key pair), token caching and refresh, the exact request headers and payload, every response classification, per-device isolation, the expired-token retry, transient failures, and that no result or summary ever contains a token or key. `deno check` on `index.ts` is clean, which the original was not.
- **Not tested:** a real request to Apple. That needs the secrets, a deployed function and a device (Stages C and D).

## Exit gate

| Item | Status |
|---|---|
| Web Push regression checks pass | Recipient and wording rules pinned by unit tests; the live check needs the deploy (Stage C). |
| Sandbox APNs accepts a correctly signed request | Not started (Stage B/C: needs the secrets and a deployed function). |
| A development device receives assignment, update, comment and status notifications | Not started (Stage D). |
| Foreground presentation is verified | Code done; needs a device (Stage D). |
| A tap opens the correct chore after cold launch, warm launch and session restoration | Verified in UI tests for the sign-in case; device check pending (Stage D). |
| Invalid-token cleanup is evidenced | Logic and classification unit-tested; live evidence needs a device (Stage D). |
| TestFlight/production APNs environment validated separately | Not started. |

## Next

Stage C: the user sets the four secrets, then, with explicit go-ahead, I apply the small `anon` migration and deploy `send-push`. Then Stage D on the user's iPhone. See `docs/phase-5-deploy-runbook.md`.
