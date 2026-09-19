# PapaTodos

Native iOS client for PapaBoard, a family chore-tracking app backed by Supabase. See [specification.md](specification.md) for the full plan, scope, and phase breakdown, and [AGENTS.md](AGENTS.md) for operational notes when working on this repo.

## Status

Phases 0, 1 and 2 are complete (foundation; sign-in and shared data; Home, search, Settings). Phase 3 (create/edit/delete chores, links in descriptions, photos) is code-complete and simulator-verified; its live smoke test and device checks are still open. Chore detail/comments and notifications are not built yet. See `docs/phase-N-validation.md` for what has actually been verified, not just implemented.

Not yet done: source implementation of any user-facing feature, Supabase migration changes, Edge Function deployment, APNs delivery, or any TestFlight/production release step.

## Requirements

- Xcode 27.0, iOS/iPadOS 27.0 SDK
- An Apple Developer account for device/signing (development team `D58U53H2X6`)

## Getting started

```bash
cp Configuration/Local.xcconfig.example Configuration/Local.xcconfig
# then fill in the real Supabase project URL and publishable key
```

Open `PapaTodos.xcodeproj` in Xcode, or build from the command line:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=<verified-simulator-id>' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO
```
