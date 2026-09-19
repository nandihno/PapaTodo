# Phase 1 validation — Authentication and shared data services

Date: 2026-09-19
Phase scope: specification.md section 14, "Phase 1 - Authentication and shared data services"

**Status: code complete and verified. Exit gate met**, with the live authenticated checks (sign-in, relaunch persistence, live RLS reads, sign-out, wrong-password message) confirmed by the user on a physical iPhone. The opt-in `LiveBackendReadTests` simulator run has not been executed; it is optional now.

## Files and behavior changed

- `Services/Supabase/`: `SupabaseClientFactory` (publishable key only, SDK Keychain session storage), `SupabaseAuthenticating`, `SupabaseChoreRepository`, `SupabaseProfileRepository`, `SupabaseCommentRepository`, `SupabaseErrorMapper`.
- `AppEnvironment.live(configuration:)` added; `ProfileRepository` protocol and fixture added; all service protocols are now `nonisolated`.
- `Authenticating.authEvents()` added (sign-in / sign-out / expiry stream) and `AuthEvent` model.
- `AppSession` rewritten around a `Phase` state machine: `restoring`, `signedOut(reason:)`, `signedIn`, `restoreFailed`. Unrecoverable refresh failure or a 401 returns to sign-in with a "session expired" message; offline restore is recoverable (retry) and does not sign the user out.
- Domain: `ProfileSummary`, `DataServiceError` (user-safe messages, no raw server text); `Chore` gains embedded `assignedProfile` / `createdProfile` / `attachments`; `Profile` tolerates null `personalisation`.
- UI: `SignInView` (email/password content types, duplicate-submit guard), `ContentView` phase switch, `SignedInStatusView` (read-only proof of live reads; **no create/update/delete UI**). `PapaTodosApp` uses live config, or fixtures with `-UITestFixtures`.
- Chore/comment write methods on the live repositories throw `DataServiceError.notAvailableYet` (Phases 3-4).
- **Relational-select fallback: deliberately not implemented.** Live FK names (`chores_assigned_to_fkey`, `chores_created_by_fkey`, `chore_attachments_chore_id_fkey`, `chore_comments_author_id_fkey`) were confirmed by read-only query on 2026-09-19, so PapaBoard's primary select is valid and the spec allows a fallback only where live evidence requires it.

## Build

`xcodebuild ... -destination 'generic/platform=iOS Simulator' build` — **BUILD SUCCEEDED** under Swift 6 mode.

## Tests actually executed (simulator 89A541D1-CDB7-40F5-A60F-E8117BBD7A72)

- `PapaTodosTests`: **58 tests in 13 suites passed**, 1 skipped by design (`LiveBackendReadTests`, needs credentials). New: `AppSessionTests` (restore, expiry, offline retry, sign-in/out, user sign-out not mistaken for expiry, server-side expiry event), `RecordDecodingTests` (relational-shape JSON, null description/personalisation, fractional timestamps), `SupabaseServiceBoundaryTests` (stubbed transport: select shape, 401 to session-expired, 500, offline, writes blocked with zero network traffic), `SupabaseErrorMapperTests`.
- `PapaTodosUITests`: **2 passed** (launch; fixture sign-in with bad then good credentials, and sign-out).

## Simulator journeys

- Live-config launch with no saved session lands on the sign-in screen (screenshot reviewed).
- Fixture sign-in/sign-out via UI test.

## Physical-device checks

- 2026-09-19: user reported a successful sign-in with a real family account on a physical iPhone 17 Pro Max (built and run from Xcode, live config). Reported by the user; not independently observed from this session.
- 2026-09-19: user also reported, on the same device, that session persistence after force-quit/relaunch, the live chore count on the status screen, sign-out, and the wrong-password message all passed. Reported by the user; the chore count value was not shared with this session.

## Live backend checks (read-only)

- FK names and column types/nullability re-verified against the live schema; live rows have no empty-string or non-http(s) URLs, so strict `URL` decoding is safe today.
- Unauthenticated (anon key) reads of `chores`, `profiles`, `chore_comments`, `chore_attachments` all returned zero rows (HTTP 200, `[]`), consistent with RLS requiring an authenticated user.
- No production data was mutated and nothing was deployed. No service-role key exists in the app.

## Remaining (optional)

The gate is met by the device checks above. This is an additional automated check:

1. Confirm the session persists after force-quit and relaunch (simulator or device). Sign-in itself is already confirmed on a device.
2. Run the opt-in live read test:

```bash
TEST_RUNNER_PB_TEST_EMAIL='<email>' TEST_RUNNER_PB_TEST_PASSWORD='<password>' \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project PapaTodos.xcodeproj -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=89A541D1-CDB7-40F5-A60F-E8117BBD7A72' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  -only-testing:PapaTodosTests/LiveBackendReadTests CODE_SIGNING_ALLOWED=NO
```

3. Record the `LIVE-READ:` counts it prints (counts only, no content) here.
4. Physical-device checks: not applicable in this phase.

## Known limitations

- Real token-refresh-failure behavior against the live server is covered by mapping unit tests and a fixture expiry event, not yet observed live.
- `SignedInStatusView` is a placeholder replaced by the Home shell in Phase 2.
- A malformed user-entered avatar URL in the database would fail decoding of the containing list (strict `URL`); revisit with Phase 2 avatar editing.
- Existing Phase 0 note stands: RLS on `chores`/`chore_comments`/`profiles` is permissive for any authenticated user.
