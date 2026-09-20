# Phase 5 plan — Native APNs and shared notification delivery

Date: 2026-09-20. **Status: plan for approval; nothing implemented, no backend change made.**

## What exists today (read-only findings)

- **`send-push` (deployed v2, `verify_jwt: true`) is identical to the PapaBoard repo source.** It validates the caller's JWT, reads the chore, derives recipients on the server (assignee and creator, minus the caller; only `chore-assigned` and `due-soon` target the assignee alone), de-duplicates `chore-assigned` through `notification_deliveries` (inserted before sending), sends Web Push with VAPID, and deletes subscriptions that return 404/410. It refuses to run at all unless the VAPID secrets are set. Its Web Push payload's `url` is always `/`, so it carries no chore id.
- **`notification_devices` and the `register_notification_device` / `unregister_notification_device` RPCs are already live** (0 iOS devices registered; 4 Web Push subscriptions and 4 delivery rows exist). The migration file in PapaBoard is still untracked. Review: RLS is own-rows-only, the RPCs are `security definer` with an empty `search_path` and reject unauthenticated callers, tokens must be lowercase hex, and `(bundle, environment, token)` is unique so a token re-registered by another signed-in user moves to that user. One hygiene gap: the register RPC is executable by `anon` (harmless, since it rejects a null user, but it should be revoked).
- **The app already has** the entitlement (`aps-environment`), `AppConfiguration.apnsEnvironment` (sandbox for Debug, production for Release), the bundle id, and an `AppRouter` that keeps a pending chore route until sign-in completes.
- **APNs key:** name `nandoPushKey`, Key ID `9KA75NDGRT`, Team ID `D58U53H2X6`. The `.p8` has not been downloaded yet.

## Stages

### A. Native client (no backend change, no key needed)
1. `NotificationRegistering` service and an `AppDelegate` adaptor: permission request (user-initiated), `registerForRemoteNotifications`, hex token, `register_notification_device` RPC with the configured environment and bundle id. Re-register on each sign-in and launch (tokens change); tokens are never logged in full.
2. Sign-out unregisters the token best-effort (sign-out still completes if it fails), per spec 9.1.
3. Permission and registration status UX: a Settings section (status, Enable, Open Settings when denied) and a one-time contextual prompt on Home while permission is undetermined (decision #5).
4. Foreground presentation (`willPresent`: show the banner and refresh) and tap routing (`didReceive`: `choreId` into `AppRouter`, opening the detail screen after cold launch, warm launch and session restoration).
5. Dispatch: after a successful create/edit/status change/comment, call `send-push` non-blockingly with the same event names the web uses. A notification failure never fails the action.
6. Tests with fakes: registration, permission states, sign-out unregister, route retention, dispatch never blocking.

### B. Backend, PapaBoard repo (written and tested locally; nothing deployed)
1. Review and commit the `notification_devices` migration, plus a small migration to revoke the register/unregister RPCs from `anon`.
2. Extend `send-push` to also deliver over APNs: ES256 provider token from the `.p8` (cached), HTTP/2 request to the sandbox or production host chosen per device row, payload with the same title/body plus `choreId` and `eventType`, `apns-topic` = bundle id, collapse id from the existing tag. Recipient rules and the delivery ledger stay exactly as they are and are shared by both channels.
3. Safe diagnostics (status and Apple's reason string only, never tokens or keys) and cleanup: a device row is deleted on `410 Unregistered` and on token/topic errors.
4. Web Push behavior unchanged, checked by a regression test of the pure logic.

### C. Needs your authorization or action
- **You set the secrets** (Supabase dashboard or CLI): the `.p8` contents, Key ID, Team ID and bundle id. I never see the file.
- **Deploying the function** changes shared backend behavior for the whole family, so it needs your explicit go-ahead. I'd deploy, run the Web Push regression, then a sandbox APNs test.
- **Applying the two small migrations** (also needs your go-ahead).

### D. Verification on a real device (spec exit gate)
Sandbox APNs accepts a signed request; your device receives assignment, update, comment and status notifications; foreground presentation; tapping opens the right chore from cold launch, warm launch and after session restoration; an invalid token is cleaned up; Web Push still works. TestFlight/production APNs is qualified separately before release.

## Risks

- **Deno to APNs over HTTP/2.** Deno's `fetch` speaks HTTP/2, and this is a common pattern, but it must be proven in the Supabase runtime; the first sandbox send is the test. Fallback: a small relay on a different runtime.
- **Simulators can't be relied on for real APNs delivery**, so the end-to-end check needs your device (Debug builds use the sandbox host).
- Native actions notify other people, so early testing should use a test chore assigned between you and one other family member you've told.
