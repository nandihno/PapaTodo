# Agent guidance for PapaTodos

This file is for AI coding agents (and anyone else picking up this repo cold). The full plan lives in [specification.md](specification.md) — read it before doing anything nontrivial here. This file only captures operational details the spec doesn't cover and gotchas already paid for once.

## Repository boundaries

- This repo (`PapaTodos`) owns the native iOS client only: Xcode project, Swift source, native config, tests, assets.
- The shared Supabase backend (migrations, RLS, Storage policies, the `send-push` Edge Function) is owned by a **separate** repo: `~/dev/NandoProjects/PapaBoard`. Never copy backend migrations into this repo. Backend changes get implemented and reviewed there, then referenced from this repo's validation docs.
- Work one phase at a time (specification.md section 14). Confirm which phase is requested before implementing, and stop at the phase's exit gate for review rather than continuing into the next phase unprompted.

## Current status

See `docs/phase-N-validation.md` files for what's actually been done and verified, per phase. Do not trust a summary in chat history over what's recorded there — re-check current state before continuing.

## Build and test

Always pass an explicit `-derivedDataPath`. The default `~/Library/Developer/Xcode/DerivedData` location is not reliably writable in sandboxed tool environments (permission/lock errors on SPM package checkouts) — this is not optional, not just a style preference.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=<verified-simulator-id>' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO
```

Wrap long runs so a hang can't block you: `xcodebuild` sometimes **hangs after the tests finish when any test failed** (the run is over but the process never exits, and macOS has no `timeout`). Use `perl -e 'alarm 590; exec @ARGV' xcodebuild ...` and read the log. Exit 142 means the alarm fired; the results are still in the log.

Get a valid simulator id with `xcrun simctl list devices available`. Never assume a build/test result — a successful `build-for-testing` proves compilation only, not that tests executed (specification.md section 13.4).

## Editing project.pbxproj

This project uses Xcode's newer file-system-synchronized-group format (`objectVersion = 110`). Two tempting shortcuts are unsafe here:

1. **The `xcodeproj` Ruby gem** only supports up to `objectVersion 100`. A no-op open+save round-trip silently dropped the existing `validationLevel` attribute and rewrote content it didn't need to touch. Don't use it to *save* this file. (Read-only inspection is fine if you verify you didn't write.)
2. **Driving Xcode via GUI/computer-use automation** — Xcode is only grantable at "click" tier (no typing/shortcuts) in this harness, so you can't fill in target names or package URLs this way.

The working approach: hand-edit `project.pbxproj` as text (it's a plist), generate fresh 24-hex-char object IDs (`openssl rand -hex 12 | tr 'a-f' 'A-F'`), insert new `PBX*`/`XC*` stanzas following the existing alphabetical section order, then verify with `plutil -lint`, `xcodebuild -list`, `-resolvePackageDependencies`, `build-for-testing`, and an actual `xcodebuild test` run. Don't trust that an edit is correct just because the file parses — build and run something.

Xcode itself may silently reorder objects within sections (alphabetically by ID) the next time it touches the file via `xcodebuild`. This is cosmetic normalization, not a real change — diff before assuming something broke.

## xcconfig gotcha

`//` starts a comment in `.xcconfig` files, including inside a URL value. To put `https://...` in an xcconfig value, break up the slashes: `https:/$()/host` (the empty `$()` build-setting reference prevents `//` from being parsed as a comment start). See `Configuration/Config.xcconfig` and `Configuration/Local.xcconfig.example`.

## Configuration and secrets

- `Configuration/Config.xcconfig` (committed) sets empty defaults for `PB_SUPABASE_URL`/`PB_SUPABASE_ANON_KEY`, then `#include? "Local.xcconfig"`.
- `Configuration/Local.xcconfig` (gitignored) holds real values — copy `Local.xcconfig.example` to get started.
- The app target uses a **physical** `Configuration/Info.plist` (`INFOPLIST_FILE`, not `GENERATE_INFOPLIST_FILE`). Xcode's generated-Info.plist mode (`INFOPLIST_KEY_<Name>`) only supports a curated list of Apple's own keys, not arbitrary custom ones — confirmed empirically when a plain test key was silently dropped from the built plist. Custom keys (`PBSupabaseURL`, `PBSupabaseAnonKey`) use `$(VAR)` substitution in the physical plist instead. That file must live **outside** any `PBXFileSystemSynchronizedRootGroup` folder (e.g. not inside `PapaTodos/`) or Xcode auto-adds it to Copy Bundle Resources too, colliding with `ProcessInfoPlistFile`'s own output.
- These are read by `PapaTodos/Configuration/AppConfiguration.swift`. The Supabase key here is the publishable/anon key, safe for client bundles (RLS enforces access, not secrecy of this key). Never add a service-role key, APNs private key, or Web Push VAPID private key to this repo in any form.

## Swift 6 default actor isolation gotcha

This project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which implicitly MainActor-isolates **every** declaration that doesn't say otherwise — not just SwiftUI views. This bit plain `struct`/`enum` domain types (`AppConfiguration`, `Chore`, `DueTone`, `ChoreSort`, etc. — even a stored-property key path like `\.title` fails from a nonisolated context) and even the synchronous initializers of plain `actor` types (`FixtureChoreRepository()` etc.).

- **Plain value types and enum namespaces** (domain models, `Domain/Rules/*`, `AppConfiguration`): mark the type declaration `nonisolated`. This is valid and is the fix.
- **`actor` types**: you cannot write `nonisolated init` on an actor's synchronous initializer — the compiler rejects it outright ("`nonisolated` on an actor's synchronous initializer is invalid"). Don't fight this: leave the actor MainActor-isolated and mark whatever calls its plain initializer synchronously (test functions, `AppEnvironment`) as `@MainActor` instead. See `FixtureAuthenticating`/`FixtureChoreRepository`/`FixtureCommentRepository` and `FixtureRepositoryTests`/`AppRouterTests` for the pattern.
- Genuinely UI-bound observable state (`AppSession`, `AppRouter`) should stay `@MainActor` — that one's correct, not a workaround.
- **Closures handed to UIKit/SwiftUI that run off the main thread** (for example `UIColor { traits in ... }` dynamic providers) inherit MainActor isolation too, and trap with `dispatch_assert_queue` when SwiftUI resolves them on a render thread. Build them inside a `nonisolated` function (see `personUIColor` in `Views/Support/ColorSupport.swift`). This only crashes at runtime, so a green build doesn't prove it's fine; run the UI tests.
- **`UNUserNotificationCenterDelegate` callbacks must stay main-actor.** A `nonisolated` async `didReceive` finished on a background thread and the system's follow-up UIKit call (snapshot/state restoration) aborted the app on every notification tap. `AppDelegate` conforms with `@MainActor UNUserNotificationCenterDelegate`. Simulated taps in UI tests do not exercise this; only a real APNs tap on a device does.
- When adding a new pure-logic type, build it and run its tests before assuming it's fine; this isolation inference is easy to miss until the compiler flags a specific call site.

## Supabase MCP access

This session has read/write access to the live Supabase project (`apaeocgssnkncputzolu`, name `choresDeleon`) via a connected MCP server. Prefer read-only calls (`list_tables`, `execute_sql` with SELECT, `get_advisors`) for schema/RLS audits. Anything that mutates production data or deploys migrations/functions needs explicit user authorization first, per specification.md section 11.1.

## Testing gotchas learned the hard way

- **Shared URLProtocol stub:** `StubURLProtocol` holds global state, so every test that uses it must live in the one `@Suite(.serialized)` (`SupabaseServiceBoundaryTests`, extended in `LiveWriteBoundaryTests.swift`). Separate suites run in parallel and trample each other, which shows up as random wrong-status failures. `#require` cannot be nested inside another `#require`.
- **Raw strings:** a `#"..."#` literal ends at the first `"#`, so JSON containing `"#RRGGBB"` needs `##"..."##`.
- **Lazy lists:** only rows that have been scrolled into view exist in the accessibility tree; UI tests use the `reveal` helper before touching rows below the fold.
- **iOS 26 confirmation dialogs** on iPhone show only the non-cancel buttons; users (and tests) dismiss them by tapping outside. Don't look for a "Cancel"/"Keep Editing" button.
- **Card taps:** a `.plain` Button only hit-tests drawn content, so the card label needs `.contentShape(Rectangle())`; otherwise tapping the middle of a card does nothing.
- **Dark mode:** the simulator's appearance switch (`simctl ui appearance`, `XCUIDevice.appearance`) did not take effect on this setup, so screenshots use the in-app `-UITestDarkMode` launch argument.
- **Launch arguments** (fixtures only): `-UITestFixtures`, `-UITestFailFirstLoad`, `-UITestDarkMode`, `-UITestSeedPhoto`, `-UITestNotificationStatus notDetermined|denied|authorized` (fake notification permission; fixture runs default to `authorized` so the Home prompt doesn't push the list down), `-UITestNotificationTapChore <uuid>` (as if a notification about that chore was tapped before sign-in), `-UITestStorageRefusesDeletes` (the fixture bucket refuses file deletes, like the live one today), `-UITestRemoteComment` (another client comments on the recycling chore about 1.5 s after the detail screen subscribes).
