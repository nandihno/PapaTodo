# Phase 0 validation — Foundation and contract audit

Date: 2026-09-18
Phase scope: specification.md section 14, "Phase 0 - Foundation and contract audit"

## Files and behavior changed

- `.gitignore` added (xcuserdata, DerivedData, local config/secrets, Claude Code session state)
- Untracked two committed Xcode user-state files (`UserInterfaceState.xcuserstate`, `xcschememanagement.plist`)
- Added `PapaTodosTests` (Swift Testing unit test target) and `PapaTodosUITests` (XCUITest target)
- Added an explicit shared scheme: `PapaTodos.xcodeproj/xcshareddata/xcschemes/PapaTodos.xcscheme`
- Added Supabase Swift via SPM, pinned to exact version `2.55.2`, product `Supabase`; `Package.resolved` committed
- Added typed configuration loading: `Configuration/Config.xcconfig` (committed, no secrets), `Configuration/Local.xcconfig` (gitignored, real values), `Configuration/Local.xcconfig.example` (committed template), `Configuration/Info.plist` (physical, replaces generated Info.plist), `PapaTodos/Configuration/AppConfiguration.swift`
- Added `AGENTS.md`, updated `README.md` with status/setup, added `docs/phase-N-validation.md` template
- Recorded all ten specification.md section 18 decisions; implemented the four with code to change (display name, device family, Swift 6 mode) — see "Decisions recorded" below
- Added the app/session/router composition skeleton (`PapaTodos/App/{AppSession,AppRouter,AppEnvironment}.swift`) and Codable/Sendable domain contracts (`PapaTodos/Domain/{Models,Protocols,Rules}/`), plus deterministic fixture services (`PapaTodos/Services/Fixtures/`) — see "Architecture skeleton and domain rules" below
- Added `docs/papaboard-parity-checklist.md`, freezing what's been ported against the actual PapaBoard source (with an important caveat about uncommitted PapaBoard changes — see that doc)

## Build

Command run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO build
```

Result: **BUILD SUCCEEDED** (app target, with Supabase Swift 2.55.2 linked and the physical `Configuration/Info.plist` producing `PBSupabaseURL`/`PBSupabaseAnonKey` correctly — confirmed by `plutil -p` on the built app's `Info.plist`).

## Test compilation

Command run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build-for-testing \
  -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=89A541D1-CDB7-40F5-A60F-E8117BBD7A72' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO
```

Result: **TEST BUILD SUCCEEDED** for both `PapaTodosTests` and `PapaTodosUITests`.

## Tests actually executed

Command run (unit tests):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project PapaTodos.xcodeproj -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=89A541D1-CDB7-40F5-A60F-E8117BBD7A72' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  -only-testing:PapaTodosTests CODE_SIGNING_ALLOWED=NO
```

Result: **TEST SUCCEEDED** — 30 tests across 8 suites, all passing:

- `PapaTodosTests` (config loading), `DueDateRuleTests`, `ChoreDueStateTests`, `ChoreSortTests`, `ChoreFilterTests`, `ChoreSearchTests` (domain rules ported from PapaBoard — see `docs/papaboard-parity-checklist.md`), `FixtureRepositoryTests` (deterministic fake CRUD/auth/comments), `AppRouterTests` (pending-route deep-link retention).

Command run (UI tests):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project PapaTodos.xcodeproj -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=89A541D1-CDB7-40F5-A60F-E8117BBD7A72' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  -only-testing:PapaTodosUITests CODE_SIGNING_ALLOWED=NO
```

Result: **TEST SUCCEEDED** — `PapaTodosUITests.testAppLaunches()` passed (9.2s), launching `org.nando.PapaTodos` for real on the simulator.

## Simulator journeys executed

- App launch only (via the UI test above). No feature screens exist yet — `ContentView.swift` is still the SwiftUI template.

## Physical-device checks executed

None. Not required for Phase 0's scope (no APNs, PhotosPicker, EventKit, or pasteboard code exists yet).

## Backend changes reviewed/deployed

Read-only audit only, no changes made or deployed:

- Confirmed live Supabase project `apaeocgssnkncputzolu` (name `choresDeleon`) schema matches specification.md section 6 for `profiles`, `chores`, `chore_comments`, `chore_attachments`, `push_subscriptions`, `notification_deliveries`, `notification_devices`.
- **Correction to specification.md section 4.3**: `notification_devices` table and `register_notification_device`/`unregister_notification_device` RPCs are already deployed live (not just an untracked draft migration), though not tracked in `supabase_migrations.schema_migrations` — needs reconciliation with the PapaBoard repo's migration file in a future phase.
- **Gap found and fixed 2026-09-18**: the `supabase_realtime` publication had zero tables attached, so the web app's existing comment-Realtime subscription (`ChoreDetailScreen.jsx`) was silently idle. Read the actual subscription code first (it just refetches on any event — no manual merge/dedup logic to worry about), then applied `202609180001_enable_chore_comments_realtime.sql` (additive only, no RLS/schema change) directly to the live project and committed it in the PapaBoard repo. Verified via `pg_publication_tables`.
- **Gap found**: RLS on `chores`, `chore_comments`, `profiles` is fully permissive for any authenticated user (not scoped to owner/assignee). `chore_attachments`, `push_subscriptions`, `notification_devices` are correctly scoped.
- Minor: `chore-images` storage bucket is public with no size/MIME restrictions; a few low-severity security advisor lints (mutable search_path, SECURITY DEFINER functions callable by anon — but internally guarded); leaked-password protection disabled in Auth.
- `send-push` Edge Function is deployed (ACTIVE, version 2) but only handles Web Push, per spec.

Full detail retained in this session's memory (`project_supabase_audit_2026-09-18`).

## Architecture skeleton and domain rules (section 14 items 9, 10, 12)

- **App composition** (`PapaTodos/App/`): `AppSession` and `AppRouter` are `@Observable @MainActor` per specification.md section 7.1 (they're genuinely UI-bound state); `AppEnvironment` bundles the three protocol-typed dependencies with a `.fixture()` factory. `PapaTodosApp.swift` wires `AppSession`/`AppRouter` into the environment and calls `session.restore()` on launch — `ContentView.swift` itself is untouched (still the template; that's Phase 2's job).
- **Domain contracts** (`PapaTodos/Domain/`): `Chore`, `ChoreDraft`, `Profile`, `ChoreComment`, `ChoreAttachment`, `AppSessionRecord`, `ChoreStatus` (all Codable/Sendable, matching specification.md section 6's DB field names via `CodingKeys`), plus the three protocols from section 7.4 (`Authenticating`, `ChoreRepository`, `CommentRepository`) verbatim.
- **Due-date and list rules** (`PapaTodos/Domain/Rules/`): `DueDateRule` (local-noon sentinel detection), `ChoreDueState` (tone + sort rank/key), `ChoreSort`, `ChoreFilter` (Mine/All/Done), `ChoreSearch` — all ported directly from PapaBoard's actual source (`src/lib/dueDates.js`, `src/screens/HomeScreen.jsx`), not reimplemented from the spec's prose description. See `docs/papaboard-parity-checklist.md` for the file:line mapping and what's deliberately not ported yet.
- **Deterministic fixtures** (`PapaTodos/Services/Fixtures/`): `FixtureAuthenticating`, `FixtureChoreRepository`, `FixtureCommentRepository` — in-memory actors, never touch Supabase, used by `AppEnvironment.fixture()` and by the test suite directly.
- **Real Swift 6 concurrency findings, not just theoretical risk**: this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting turned out to implicitly MainActor-isolate *every* unannotated declaration — plain structs/enums (`Chore`, `DueTone`, `ChoreSort`, etc.) and even synchronous initializers on plain `actor` types, not just SwiftUI-adjacent code. Every pure-domain type needed an explicit `nonisolated` to be usable from plain (non-`@MainActor`) test functions; the fixture actors instead needed their *test callers* marked `@MainActor` (`nonisolated` on an actor's synchronous initializer is a compiler error — that's genuinely invalid syntax, not a style choice). Recorded in the `swift6-default-isolation-papatodos` memory for future files.

## Known limitations and follow-up work

- `project.pbxproj` was hand-edited (not via the `xcodeproj` gem or Xcode GUI automation — see AGENTS.md for why). Future structural project changes should follow the same manual-edit-then-verify approach until a compatible tool exists.
- `Configuration/Local.xcconfig` on this machine currently holds the real Supabase publishable key and project URL for local development; it is gitignored and was never committed.
- `AppEnvironment` has no `.live` factory yet — Phase 1 adds a Supabase-backed implementation of the three protocols. Until then the running app only ever uses `.fixture()`.
- The parity checklist covers due-date/sort/filter/search only. Attachments, comments UI, notifications, rich text, and calendar behavior haven't been read from PapaBoard source yet — each is scoped to its own later phase.

## Decisions recorded (specification.md section 18)

All ten answered 2026-09-18/19:

1. Product display name: **Papa Todos** (corrected 2026-09-19; originally recorded here as "Papa Tools" in error) (`CFBundleDisplayName` only — Xcode target name, bundle identifier `org.nando.PapaTodos`, folder names, and the git repo remain PapaTodos; explicitly scoped this way to avoid bundle-identifier churn ahead of any TestFlight/App Store record).
2. Deployment floor: **iOS 27.0+** (matches the existing project default, no change needed).
3. Device family: **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1` on all three targets, iPad-specific orientation key removed from `Configuration/Info.plist`). Supersedes the spec's "iPhone-first, universal buildable" default — this project no longer builds a universal target.
4. Concurrency: **Swift 6 language mode**, enabled now (`SWIFT_VERSION = 6.0` on all three targets). Surfaced one real issue immediately: the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting made `AppConfiguration` implicitly MainActor-isolated, which broke calling it from a nonisolated test context. Fixed by marking the type `nonisolated` — it's a plain Sendable value type doing synchronous Info.plist reads, not UI-bound state, so it shouldn't have been MainActor-isolated in the first place.
5. Notification controls: **Settings, with a contextual one-time Home prompt** while permission is undetermined (spec default). Not yet implemented — no Settings/Home screens exist.
6. Rich-text editing: **exact parity** with the web app's formatting (spec default, full Phase 3 estimate stands). **Revised 2026-09-19 (Phase 3 start): links only.** The editor edits text and links; existing formatted descriptions still render in full and are protected from silent loss. See `docs/phase-3-validation.md`.
7. Copied-image paste: **required** for v1, in addition to multi-photo selection (spec default).
8. Distribution: **TestFlight-only** initially; a standard App Store release is a separate later decision (spec default).
9. Backend ownership: **PapaBoard remains the permanent owner** of shared Supabase migrations, RLS, and Edge Functions (spec default; already the pattern followed for the Realtime fix above).
10. APNs/Apple Developer readiness: reported **fully ready** — active paid membership, push notifications capability already enabled for the bundle ID, and an APNs auth key already generated. Not independently verified from this session (no tooling access to the Apple Developer portal); treat as a claim to confirm at the start of Phase 5.

Verified after applying items 1-4 (the only ones with code to change today): clean build succeeds, `Info.plist` shows `CFBundleDisplayName = Papa Tools` (at the time; now Papa Todos) and `UIDeviceFamily = [1]`, and the full test suite (`PapaTodosTests` + `PapaTodosUITests`) passes under Swift 6 strict concurrency checking.

## Deployment-boundary checklist (specification.md section 3.3)

- [x] specification written
- [x] native code implemented locally (test targets, config loader, app/session/router composition, domain contracts and rules, fixture services — no live-Supabase or UI feature code yet)
- [x] native build succeeded
- [x] test bundles compiled
- [x] simulator tests executed
- [x] Supabase migration reviewed (read-only audit of live schema/RLS/Realtime/functions)
- [x] Supabase migration deployed (`202609180001_enable_chore_comments_realtime.sql`, additive-only, applied to `apaeocgssnkncputzolu` and verified via `pg_publication_tables`; reviewed and committed in the PapaBoard repo, not this one)
- [ ] Edge Function deployed
- [ ] APNs accepted a request
- [ ] a physical device received and opened the notification
- [ ] TestFlight build uploaded
- [ ] family UAT passed
- [ ] production release approved
