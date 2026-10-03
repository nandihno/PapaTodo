# Phase 8 validation — Viewing chores offline

Recorded 2026-09-29. Plan: [phase-8-offline-plan.md](phase-8-offline-plan.md).

iOS only. No backend changes: nothing in the PapaBoard repo or the live Supabase project was touched.

## What was built

- **On-device store:** `SQLiteChoreCache`, using Apple's built-in SQLite, so no new dependency and no project-file edits. It lives at `Application Support/OfflineCache/chores.sqlite`, excluded from iCloud backup, with `secure_delete` on.
  - Up to **10 chores per account**. When an 11th is saved, the **least recently viewed** one is dropped.
  - Each entry is a JSON `CachedChore`: the chore, its comments, and the people it mentions.
  - Photos are kept in their own table and deleted along with their chore. They're capped at **150 MB** in total: the least recently viewed *other* chores are evicted to make room, and a photo that can never fit is skipped.
  - An entry that can't be read (damaged, or from an older app version) is dropped instead of crashing. Cache failures never break the live app.
- **Chore screen:**
  - The saved copy shows first, then Supabase is asked for the latest.
  - The banner shows "Getting the latest…", then a 2-second "Up to date" (also announced to VoiceOver). If the fetch fails, it shows "Saved copy · updated *X* ago" and **Refresh** (or "Couldn't get the latest" when there's no saved copy).
  - Each confirmed fetch replaces the saved copy. Status changes, sent comments and live comments update it too.
  - A chore that no longer exists loses its saved copy.
  - Reading a saved copy offline counts as viewing it.
  - A copy saved while the comments failed to load is **not** kept, because it would claim to be newer than it is.
- **Read-only saved copies:**
  - Edit, the ⋯ menu, status, Mark as Done and comments are disabled, with "Reconnect to make changes."
  - Save to Calendar stays available, since it only writes to the phone.
  - A chore opened from a live Home list stays editable, as before.
- **Photos:** `ChorePhotoStore` serves a saved photo first, **even online**: every upload has its own storage path, so a saved photo is never out of date. Otherwise it downloads the photo, sharing one download among simultaneous requests, and keeps it if the chore is saved. After each save, any missing photos of the chore are fetched in the background. The detail screen, full-screen viewer and saved-for-offline cards use it; the live Home cards still use `AsyncImage`.
- **Home:** if the first load fails, Home shows **Saved for offline (n)**, most recently viewed first, with Try Again. Retrying keeps the list on screen, and a successful load replaces it.
- **Cold launch offline:**
  - If the saved sign-in can't be renewed, the "Can't restore session" screen offers **View Saved Chores (n)**. That opens the normal app shell for that account, in the new `AppSession.Phase.savedChoresOnly`, without push registration.
  - The first request that renews the sign-in moves the app to `.signedIn` by itself.
  - A notification tapped while offline opens that chore's saved copy.
- **Privacy:** saved copies are erased (`AppSession.onSessionEnded` → `removeAll`) on sign-out, on session expiry (including while browsing saved chores), and when a launch finds no saved session.

### Differences from the plan

- The Home and restore-screen paths reuse the normal app shell (`MainView`) rather than a separate read-only browser. Saved chores open exactly like live ones, and the switch back to live data is automatic.
- Only a copy loaded from the phone is read-only. A Home-list chore whose refresh fails stays editable.
- Save to Calendar isn't disabled on a saved copy.
- The `-UITestOffline` fixture was brought forward from step 7 to step 5, so each step had a real offline UI test.

## Automated evidence

Simulator: iPhone 17, iOS 27.0.

| Check | Result |
|---|---|
| Per step (unit suite + affected UI tests) | Green after every step: 396 → 406 → 407 → 414 → 418 → 425 unit tests. |
| Full run after step 4 | 414 unit tests + 48 UI tests, all pass. |
| Full run, final (step 7) | FINAL_RESULT |

New tests:
- `ChoreCacheTests` (12): eviction order, account separation, erase-all, photo cap and pruning, reopening and damaged rows, and the backup exclusion.
- `ChoreDetailOfflineTests` (11): save after a confirmed fetch, the half-fresh copy is not saved, status updates the copy, a read-only saved copy, blocked writes, refresh replaces it, viewing marks it recent, no-copy failure, a Home-list chore stays editable, a deleted chore loses its copy, the brief "Up to date".
- `ChorePhotoStoreTests` (7): saved photo first, keep only for saved chores, one shared download, failure, prefetch only missing, detail keeps photos, offline shows saved photos.
- `HomeOfflineTests` (4): saved list order, plain error when none, other accounts hidden, retry keeps the list.
- `AppSessionOfflineTests` (7): saved sign-in remembered and browsable, nothing without a saved sign-in, a later restore takes over, erase on sign-out, expiry while browsing, restore with no session, and no erase on sign-in or a failed restore.
- 4 UI tests: "Up to date" confirmation; offline Home → read-only saved copy; cold launch → View Saved Chores; notification tap offline.

New launch arguments (see AGENTS.md): `-UITestLongConfirmation`, `-UITestOffline`, `-UITestRestoreOffline`.

Flaky, unrelated: `testBulletListsContinueOnReturnAndEndOnAnEmptyBullet` failed once in a full run on 2026-09-28 and passed alone and in every later full run.

## Manual (pending, user)

On a real phone with the live backend:
1. While online, open 3–4 chores, including one with several photos. Open the full-screen viewer on one.
2. Turn on airplane mode, close the app fully and reopen it.
   - Signed in within about an hour: Home shows **Saved for offline**.
   - Otherwise: the restore screen shows **View Saved Chores**.
3. Open a saved chore: its photos show, the banner says "Saved copy · updated …", and Edit, status and comments are greyed out.
4. Turn airplane mode off and tap **Refresh**: "Up to date" appears and the controls work again.
5. Settings → Sign Out, sign back in, go offline, and confirm nothing is saved any more.
