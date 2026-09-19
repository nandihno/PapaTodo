# Phase 2 validation — Home, search, navigation, and personalization

Date: 2026-09-19
Phase scope: specification.md section 14, "Phase 2 - Home, search, navigation, and personalization"

**Status: code complete and verified. Exit gate met**, on the strength of simulator evidence plus the user's report that the app works correctly on a physical device (see below). The user did not itemize which checks were run, so the per-tab counts and the live avatar/theme writes are not individually recorded.

## Files and behavior changed

- **Shell and navigation:** `Views/MainView.swift` (NavigationStack, profile theme tint with a contrast guard, foreground refresh on `scenePhase == .active`), replacing the Phase 1 status placeholder.
- **Home:** `Views/HomeView.swift` (Mine / All / Done, `.searchable`, pull-to-refresh, loading / empty / error / retry states, stale-data banner), `Views/ChoreCardView.swift` (title, status badge, assignee avatar and name, due label, primary photo thumbnail, attachment count; one combined VoiceOver element), `Views/ProfileAvatarView.swift`.
- **Settings:** `Views/SettingsView.swift` (name and email, avatar URL validate/save/clear, theme color picker + hex field + suggested swatches + readable preview, sign-out).
- **State:** `App/HomeModel.swift` (latest-request-wins loading; a failed refresh keeps existing chores), `App/ProfileStore.swift` (bound to the signed-in user's id; only ever writes that row).
- **Domain rules (ported from PapaBoard, see the parity checklist):** `PersonColor`, `ProfileInitials`, `ThemeColor`, `AvatarURL`, `ChoreDueLabel`, `ChoreAttachments`, `HomeList` (+ `Chore.mergingCurrentUser`).
- **Backend access:** `ProfileRepository` gained `updateAvatarURL` and `updateThemeColor`; `SupabaseProfileRepository` implements them as single-row updates by primary key, merging the theme into the existing `personalisation` JSON, and treats a zero-row result as a failure. `DataServiceError.cancelled` added so cancelled requests aren't shown as errors.
- **Fixtures/test hooks:** `FixtureData` (fixed identities and five chores spanning every tab and sort bucket); launch arguments `-UITestFixtures`, `-UITestFailFirstLoad`, `-UITestDarkMode`.
- Not built here by design: chore detail and status change (Phase 4), create/edit (Phase 3), notification controls in Settings (Phase 5; spec section 9.10 lists them, decision #5 places them in Settings).

## Build

`xcodebuild ... -destination 'generic/platform=iOS Simulator' build` — **BUILD SUCCEEDED** (Swift 6 mode).

## Tests actually executed (simulator 89A541D1-CDB7-40F5-A60F-E8117BBD7A72)

Full run `xcodebuild test` on both targets: **TEST SUCCEEDED**.

- `PapaTodosTests`: **103 tests in 21 suites passed** (one skipped by design: the credentialed `LiveBackendReadTests`). New in Phase 2: parity vectors generated from PapaBoard's own JS (person hue, theme/contrast, avatar URL), `HomeListTests` (tab partition, sort order, search, current-user overlay, copy, due labels, attachments), `HomeModelTests` (load, retry, stale data kept on failed refresh, older response cannot overwrite newer, session expiry forwarded, cancellation not an error), `ProfileStoreTests` (own-row-only writes proven with a spy repository, validation before any write, theme preview/save), profile write request shape against a stubbed transport (PATCH by id, only the changed column, theme merged with existing keys, zero-row update is a failure).
- `PapaTodosUITests`: **9 tests passed**: launch; sign-in bad password then success then sign-out; Mine/All/Done counts; card VoiceOver description; search, empty state and result clearing; first-load failure then retry; Settings avatar and theme validation and save; light/dark rendering; accessibility-size layout.

## Simulator journeys and visual review

Screenshots from the UI tests were reviewed (default size light, dark, and `AccessibilityXXXL`, plus Settings in each). Findings and fixes made from them:

- **Crash found and fixed:** `Color.person` created its dynamic `UIColor` closure in a MainActor context; SwiftUI resolved it off-main and trapped. Fixed with a `nonisolated` builder and recorded in AGENTS.md.
- Weak contrast on orange/red due text: changed to primary-color text with colored icon and weight.
- Toolbar avatar initials picked up the tint and lost contrast: fixed with a concrete `Color.primary`.
- At `AccessibilityXXXL` the segmented control becomes a menu and cards stack vertically without clipping.
- Note: the simulator's own appearance switch did not take effect (even the system Settings app stayed light), so dark mode is verified through the in-app `-UITestDarkMode` hook, not the system setting.

## Physical-device checks

2026-09-19: user reported the Phase 2 build "works correctly" on a physical device, in response to a request to check the per-user tab counts and try an avatar/theme change. Reported by the user, not observed from this session, and not itemized.

## Live read-only comparison (exit gate)

Ground truth computed directly from the live database, counts only (read-only SQL):

| User (id prefix) | Mine | All | Done |
|---|---|---|---|
| 67351b76 | 2 | 2 | 3 |
| e542286d | 0 | 2 | 3 |

Both users see the same 5 rows (RLS is permissive for any authenticated user, per the Phase 0 audit). **To close the gate:** sign in as each family member on the device and confirm the three tab counts match this table and PapaBoard's. Reported as working correctly by the user on 2026-09-19 (not itemized).

## Backend changes reviewed/deployed

None deployed. The only new backend interaction is the signed-in user updating their own `profiles` row (avatar URL, theme), which was exercised only against a stubbed transport and fixtures in this session, not against the live database.

## Known limitations and follow-up work

- Cards are not tappable (detail is Phase 4).
- Profile avatar and theme writes were requested to be tried on a device with a real account; the user reported everything working but did not itemize this, so treat the live write as user-reported only.
- Search matches the raw description text, so HTML markup in rich descriptions can match (fixed with the HTML-to-text conversion in Phase 3).
- A malformed avatar URL already stored in the database would fail decoding of the whole chore list (strict `URL`); it can only be introduced through this app's or the web app's validated field, but a lenient decoder is worth adding.
- RLS on `profiles` lets any signed-in user update any row; the app enforces own-row-only itself. Tightening it is a PapaBoard-side change.
- Notification controls in Settings are deferred to Phase 5.
