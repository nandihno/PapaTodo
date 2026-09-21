# Phase 6 validation — Hardening, UAT, and release qualification

Recorded 2026-09-21/22. Build under test on devices: **1.001 (2)** via TestFlight (internal group "Family"). The first upload, 1.0 (1), was replaced because it never produced tester invitations.

## Automated evidence

| Check | Result |
|---|---|
| Clean Release build (`generic/platform=iOS Simulator`, code signing off) | Succeeded, no compiler warnings (the only output is Xcode's note that App Intents metadata extraction was skipped). |
| Unit tests (Swift Testing) | 305 tests in 38 suites, all pass. |
| UI tests (XCUITest, fixtures) | 37 tests, 0 failures, on the iPhone 17 simulator. |

A first full run failed 32 of 35 UI tests. The cause was iOS showing its "Save Password?" sheet over the app after the fixture sign-in, which swallowed the next taps; it was not an app defect (it reproduced with the previous delegate code too, and did not appear in earlier runs, so it depends on the simulator's Passwords settings). The UI-test sign-in helper now dismisses that sheet, scoped to the sheet so it cannot hit the app's own "Not Now" button.

## Release configuration

- Added `PrivacyInfo.xcprivacy`: no tracking, UserDefaults required-reason API (CA92.1), and collected data types (email, name, photos, other user content, device ID) all linked to the user for app functionality. Not yet cross-checked against Xcode's generated privacy report for the archive.
- Added `ITSAppUsesNonExemptEncryption = NO` (HTTPS only). App Store Connect's build metadata confirms "App Uses Non-Exempt Encryption: No".
- Calendar access is write-only with a usage description; photos use the system picker, so there is no photo-library permission text.
- Display name "Papa Todos", version 1.001 build 2 (bumped by hand in Xcode for the second upload), iPhone only, minimum iOS 27.0 (a deliberate choice).
- App Store Connect's metadata for build 1.0 (1) shows `aps-environment: production` and `get-task-allow: false`, i.e. a distribution-signed build.

## Archive and TestFlight

The archive and upload were done by the user in Xcode, not by me. Build 1.0 (1) validated and showed "Testing" in the Family internal group but no tester ever received an invitation ("No Builds Available", no devices). Uploading a new build sent the invitations. No cause was proven. Internal testing needs no Beta App Review. Both phones installed the TestFlight build.

## Devices and push

- Both family accounts registered on TestFlight builds as `production`: Nando (2026-09-21 01:35 UTC) and Savina (03:53 UTC). This is the first time the production path appeared in the database.
- The user reports, after testing on the phones, that notifications and the tap-to-open journey work on the TestFlight build. I did not independently see the function's response for that send, so production APNs delivery is **user-reported**, not evidenced by function logs.
- The old sandbox row for Nando's Debug install was still present when last checked. Apple should report that token dead on the next send and the function then deletes it; this has not been observed.

## Accessibility and robustness

Limited, and not the full audit the specification describes.

- Static review of the views for Reduce Motion, fixed font sizes, small targets and missing labels. One defect found and fixed: the photo viewer's double-tap reset animated under Reduce Motion. Avatars already scale with Dynamic Type.
- Existing UI tests already cover accessibility-size text, dark mode, the delete note, offline/refresh failure and expired-session flows in fixtures.
- **Not done:** VoiceOver run-through on a device, landscape checks on each screen, and an iPad check (the app is iPhone-only, so the specification's "verify the universal build on iPad" does not apply as written).

## Backend deployed state (no secret values printed)

- `send-push` is version 4, `verify_jwt` on; an unauthenticated call returns 401.
- Migration `202609200002` applied: the device functions are executable by `authenticated`, `postgres` and `service_role` only.
- The four APNs secrets are set (the user set them); the function has delivered real pushes, which it could not do without them.

## Exit gate

| Item | Status |
|---|---|
| Release build and archive succeed | Release build succeeds with no warnings; archive and upload succeeded (done by the user; build validated by App Store Connect). |
| Automated tests pass with recorded results | **Met.** 305 unit + 37 UI, 0 failures. |
| Required physical-device capability checks pass | Push (sandbox and production), tap-to-open, registration, sign-in and the chore journeys verified on devices, partly user-reported (see above). Camera/photos, calendar and the untested Phase 3 items were not re-run for this phase. |
| Backend deployed state and secrets confirmed without printing values | **Met** (see above). |
| Both users complete UAT for the critical journeys | **Not met formally.** The user reports informal testing of both accounts and considers the app at web parity, but no signed-off checklist exists. `docs/phase-6-uat-checklist.md` is ready to run; it stays unticked until you and Savina tick it. |
| Known non-blocking limitations documented | See below. |
| TestFlight upload not confused with UAT acceptance or a production release | The app has not been submitted to the App Store; TestFlight is internal only. |

## Known limitations and open items

- The specification's full UAT sign-off (`docs/phase-6-uat-checklist.md`) and the fuller accessibility audit above are not done.
- Phase 5 device checks not recorded: assigned/updated/status-changed notification types, the foreground banner and warm-launch tap as separate checks, uninstall cleanup, and a Web Push regression from a second account.
- Phase 3 items never confirmed by hand: several photos at once, editing an existing chore, removing one of two photos.
- Someone with both PapaBoard notifications on and the app registered gets one banner per device and channel (for the user, up to four). Nothing removes web subscriptions when the app is adopted.
- About 37 orphaned files remain in the `chore-images` bucket from before the delete policy existed; a one-off cleanup is not done.
- Marketing version "1.001" was chosen by hand; change it before any App Store submission if a conventional number is wanted.
- iOS 27.0 is the minimum, which excludes anyone on an older iOS.
