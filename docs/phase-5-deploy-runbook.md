# Phase 5 runbook — turning on iPhone notifications (Stage C and D)

Written 2026-09-20. Nothing in this document has been done yet. Every step that changes the live backend waits for the user's explicit go-ahead.

The code is finished and committed: PapaBoard `a58fd09` (backend) and PapaTodos `671a1f4` (app). Until the secrets below exist, the deployed function behaves exactly as it does today (Web Push only).

## Kill switch

Delete the `APNS_KEY_P8` secret (or any one of the four) and iPhone delivery switches itself off on the next request, with Web Push untouched. To go back to the old code entirely, redeploy the previous `send-push` from git history (PapaBoard commit `4d42176`).

## Step 1: you set four secrets (I never see the key)

Project `apaeocgssnkncputzolu` (choresDeleon). Secret names are exact:

| Name | Value |
|---|---|
| `APNS_KEY_ID` | `9KA75NDGRT` |
| `APNS_TEAM_ID` | `D58U53H2X6` |
| `APNS_BUNDLE_ID` | `org.nando.PapaTodos` |
| `APNS_KEY_P8` | the **entire contents** of `AuthKey_9KA75NDGRT.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

**Dashboard:** Edge Functions, then Secrets, then add each. A multi-line box accepts the key as is. If it only gives a one-line field, paste the key with each line break written as `\n`; the function repairs that.

**Or the CLI**, which reads the file itself so the key is never typed or shown:

```bash
supabase secrets set APNS_KEY_ID=9KA75NDGRT APNS_TEAM_ID=D58U53H2X6 APNS_BUNDLE_ID=org.nando.PapaTodos --project-ref apaeocgssnkncputzolu
supabase secrets set APNS_KEY_P8="$(cat /path/to/AuthKey_9KA75NDGRT.p8)" --project-ref apaeocgssnkncputzolu
supabase secrets list --project-ref apaeocgssnkncputzolu
```

`secrets list` shows names and a digest, never values. Tell me when the four names are there. Do not paste the key or its contents into the chat.

## Step 2: I apply one small migration (needs your go-ahead)

`202609200002_restrict_notification_device_functions.sql` removes `anon` (signed-out callers) from the two device functions. Additive, with a rollback in the file. I verify by reading the grants back.

## Step 3: I deploy `send-push` (needs your go-ahead)

Files: `index.ts`, `apns.ts`, `notifications.ts` (`verify_jwt` stays on). Checks I run right after:

1. The function answers: an unauthenticated call returns 401, proving the new version is live.
2. The function logs show no startup errors.
3. **Web Push regression:** trigger a normal web notification between two accounts and confirm it still arrives.

## Step 4: on your iPhone (Stage D)

1. Run a **Debug** build from Xcode on the phone (Debug uses Apple's sandbox, which matches the device token the phone gets).
2. Sign in, and turn notifications on (Home prompt or Settings). Settings should say "This device is registered." I confirm one row appears in `notification_devices` for your user.
3. Someone else in the family (a second account) acts on a chore you created or are assigned to: assign it to you, edit it, change its status, comment. Your phone should show each notification. Events you cause yourself never notify you (by design), so a second person, or the second account in the web app, is needed.
4. Foreground: with the app open, another notification should appear as a banner and the list should refresh.
5. Tap: tap a notification from a cold start (app force-quit), from the background, and after signing out and back in, and confirm each opens the right chore.
6. Cleanup evidence: uninstall the app, trigger a notification, and confirm the device row disappears (Apple answers 410 Unregistered).

The function's JSON response includes an `apns` block (devices found, sent, invalid, transient, rejected), and its logs carry Apple's reason for any failure. They never contain device tokens or the key. The first real send also proves that Deno's HTTP/2 connection to Apple works; if it doesn't, the logs will say so and the fallback is a small relay.

## Later, before release

TestFlight and App Store builds use Apple's **production** push service. That is a separate check with a TestFlight build; the same key and code handle it, chosen per device by the environment the app registered with.
