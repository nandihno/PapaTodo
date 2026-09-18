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

Result: **TEST SUCCEEDED** — `PapaTodosTests.appConfigurationLoadsFromInfoPlist()` passed (0.001s). Verifies `AppConfiguration.load()` correctly reads `supabaseURL`, `supabaseAnonKey`, `bundleIdentifier`, and derives `.sandbox` for a Debug build.

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
- **Gap found**: the `supabase_realtime` publication exists but has zero tables attached — comment Realtime (needed in Phase 4) will not work until fixed in the backend repo.
- **Gap found**: RLS on `chores`, `chore_comments`, `profiles` is fully permissive for any authenticated user (not scoped to owner/assignee). `chore_attachments`, `push_subscriptions`, `notification_devices` are correctly scoped.
- Minor: `chore-images` storage bucket is public with no size/MIME restrictions; a few low-severity security advisor lints (mutable search_path, SECURITY DEFINER functions callable by anon — but internally guarded); leaked-password protection disabled in Auth.
- `send-push` Edge Function is deployed (ACTIVE, version 2) but only handles Web Push, per spec.

Full detail retained in this session's memory (`project_supabase_audit_2026-09-18`).

## Known limitations and follow-up work

- Product name (PapaTodos vs PapaBoard), deployment floor, device-family scope, Swift 6 mode, notification UI placement, rich-text parity level, paste support, and distribution route — all ten decisions in specification.md section 18 — remain unanswered.
- `project.pbxproj` was hand-edited (not via the `xcodeproj` gem or Xcode GUI automation — see AGENTS.md for why). Future structural project changes should follow the same manual-edit-then-verify approach until a compatible tool exists.
- No PapaBoard frontend source has been inspected yet; the feature-parity checklist against an exact PapaBoard snapshot (specification.md section 4.2, section 14 item 12) is still outstanding.
- `Configuration/Local.xcconfig` on this machine currently holds the real Supabase publishable key and project URL for local development; it is gitignored and was never committed.

## Decisions recorded (specification.md section 18)

Answered 2026-09-18:

1. Product display name: **Papa Tools** (`CFBundleDisplayName` only — Xcode target name, bundle identifier `org.nando.PapaTodos`, folder names, and the git repo remain PapaTodos; explicitly scoped this way to avoid bundle-identifier churn ahead of any TestFlight/App Store record).
2. Deployment floor: **iOS 27.0+** (matches the existing project default, no change needed).
3. Device family: **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1` on all three targets, iPad-specific orientation key removed from `Configuration/Info.plist`). Supersedes the spec's "iPhone-first, universal buildable" default — this project no longer builds a universal target.

Remaining open from section 18: Swift 6 strict concurrency mode, notification control placement (Home vs Settings), rich-text editing parity level, copied-image paste requirement, distribution route, and Apple Developer/APNs credential readiness.

Verified after applying: clean build succeeds, `Info.plist` shows `CFBundleDisplayName = Papa Tools` and `UIDeviceFamily = [1]`, and the full test suite (`PapaTodosTests` + `PapaTodosUITests`) still passes.

## Deployment-boundary checklist (specification.md section 3.3)

- [x] specification written
- [x] native code implemented locally (test targets, config loader — no feature code yet)
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
