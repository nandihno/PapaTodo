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

- `Configuration/Config.xcconfig` (committed) sets empty defaults for `INFOPLIST_KEY_PBSupabaseURL`/`INFOPLIST_KEY_PBSupabaseAnonKey`, then `#include? "Local.xcconfig"`.
- `Configuration/Local.xcconfig` (gitignored) holds real values — copy `Local.xcconfig.example` to get started.
- These land in the app's Info.plist and are read by `PapaTodos/Configuration/AppConfiguration.swift`. The Supabase key here is the publishable/anon key, safe for client bundles (RLS enforces access, not secrecy of this key). Never add a service-role key, APNs private key, or Web Push VAPID private key to this repo in any form.

## Supabase MCP access

This session has read/write access to the live Supabase project (`apaeocgssnkncputzolu`, name `choresDeleon`) via a connected MCP server. Prefer read-only calls (`list_tables`, `execute_sql` with SELECT, `get_advisors`) for schema/RLS audits. Anything that mutates production data or deploys migrations/functions needs explicit user authorization first, per specification.md section 11.1.
