# Phase 8 plan — Viewing chores offline

Date: 2026-09-28. **Status: approved 2026-09-28. Step 1 (on-device store) done 2026-09-28: 12 new unit tests, full unit suite 396/396 green on iPhone 17 (iOS 27) simulator. Step 2 (detail model) done 2026-09-28: 10 more unit tests, 406/406 green. Step 3 (detail screen) done 2026-09-28: banner at the top of the detail screen, change controls disabled on a saved copy, 1 unit + 1 UI test. Step 4 (photos) done 2026-09-28: ChorePhotoStore serves saved photos first (even online; storage paths are unique per upload), shares concurrent downloads, and fetches missing photos after each save; 7 unit tests, 414/414 green. Step 5 (Home saved list) done 2026-09-28: 4 unit tests + offline UI test (via `-UITestOffline`, brought forward from step 7), 418/418 unit green. Step 6 (cold launch, notification taps, erase on sign-out/expiry) done 2026-09-28: `AppSession.savedChoresOnly` reuses the normal app shell (no push registration); 7 unit + 2 UI tests, 425/425 unit green. Step 7 (wrap-up) done 2026-09-29: specification.md section 5 notes, docs/phase-8-validation.md. Phase complete; see docs/phase-8-validation.md.**

## Goal

When you open a chore, the phone keeps a copy of it. If the connection is slow or missing, you still see that chore, including its comments and photos. Supabase stays the only source of truth: every time you open a chore the app asks Supabase for the latest version and replaces the copy.

This is a **read-only** cache. It is not the "offline-first reads and writes" excluded in specification.md section 5.2: nothing is edited offline, so there is no write queue and no conflict handling. Section 5.2 gets a note saying so.

## Decisions (2026-09-28)

1. **Up to 10 chores are kept.** When an 11th is saved, the **least recently viewed** chore is dropped.
2. **Show the saved copy first, then refresh.** Opening a chore shows the saved copy straight away and asks Supabase for the latest at the same time. The screen always says what is happening:
   - while the fetch runs: "Getting the latest…";
   - when it succeeds: a short "Up to date" confirmation, then the banner goes away;
   - when it fails: "Saved copy · updated 2 h ago" with a **Refresh** button. Pull-to-refresh does the same thing.
3. **All photos** of a saved chore are kept on the phone, within a total size cap (below).
4. **Cold launch while offline:** the "couldn't restore your session" screen offers **View saved chores**.

## Behaviour

### Saving and refreshing
- Each successful detail fetch saves the chore, its comments, and the people it mentions (names, colours, avatars) as one entry, and marks it as just viewed.
- Opening a saved chore while offline also marks it as just viewed, so chores you use keep their place.
- If Supabase says the chore no longer exists (deleted, or you lost access), its saved copy is removed and the usual "not found" screen shows.
- Photos: after a successful fetch, any photo of that chore not yet on the phone is downloaded in the background. Photos no longer attached to the chore are removed from the phone. A saved photo is shown even when online: every upload gets its own storage path, so a saved photo is never out of date. Home list cards still load photos from the network (unchanged).

### Size cap for photos
- Photos are already scaled to at most 2048 px on upload (roughly 0.5–1.5 MB each), so they are stored as-is.
- The total size of saved photos is capped at **150 MB**. If a new photo would go over, the least recently viewed *other* chores are dropped until it fits. A single chore bigger than the cap keeps only the photos that fit; the rest show a placeholder offline.

### Getting to a saved chore while offline
- **Home:** if the chore list can't load and nothing is shown yet, Home shows **Saved for offline (n)**, the saved chores ordered by when you last viewed them, with the retry control still available.
- **Cold launch:** if a saved sign-in exists but can't be refreshed because of the network, the restore-failed screen offers **View saved chores**. Only that account's saved chores are shown, read-only, until the connection is back.
- **Notification tap while offline:** opens the saved copy if there is one.

### Read-only while showing a saved copy
Status changes, comments, editing and deleting are disabled, with the hint "Reconnect to make changes". Save to Calendar stays available: it only writes to the phone's own calendar.

This applies only when the chore on screen came from the phone's saved copy. A chore opened from the Home list was fetched live this session, so if its refresh fails it stays editable (the banner still says the latest couldn't be fetched), exactly as before this phase.

### Privacy
- Every entry records which account it belongs to. Everything is erased on sign-out and when the session expires.
- The database file uses iOS file protection (readable only after the phone's first unlock since restarting) and is excluded from iCloud backups.

## Technical design

### Storage: SQLite (Apple's built-in `SQLite3` library, no new dependency)
File: `Application Support/OfflineCache/chores.sqlite`.

```sql
cached_chore(user_id, chore_id, payload BLOB, saved_at, last_viewed_at,
             PRIMARY KEY (user_id, chore_id))
cached_photo(user_id, chore_id, url, data BLOB,
             PRIMARY KEY (user_id, chore_id, url),
             FOREIGN KEY (user_id, chore_id) REFERENCES cached_chore ON DELETE CASCADE)
```

- `payload` is the JSON of a `CachedChore` (chore, comments, people, saved time). Storing JSON means new `Chore` fields never need a schema change.
- Saving updates rows in place (`ON CONFLICT ... DO UPDATE`) so a chore's photos aren't deleted on every refresh.
- A row whose JSON no longer decodes (after an app update, say) is deleted and skipped, never a crash.
- Cache failures are logged and swallowed: the cache must never stop the live app from working.

### Code
- `Domain/Models/CachedChore.swift` — the saved entry.
- `Domain/Protocols/ChoreCache.swift` — `save`, `entry`, `entries`, `markViewed`, `remove`, `removeAll`, `savePhoto`, `photo`, `storedPhotoURLs`.
- `Services/Cache/SQLiteChoreCache.swift` — the only implementation. Fixtures and tests use it with an in-memory database, so tests exercise the real SQL.
- `AppEnvironment` gains `choreCache`.
- `ChoreDetailModel` gains a `source` (`.live`, `.cached(savedAt)`) and a refresh state (`idle`, `refreshing`, `justRefreshed`, `failed`).
- `ChoreDetailView`: status banner, Refresh button, actions disabled when showing a saved copy, photos served from the cache when offline.
- `HomeModel` / `HomeView`: the Saved for offline list.
- `AppSession` / restore-failed screen: the View saved chores path.

## Steps

1. On-device store (`CachedChore`, `ChoreCache`, `SQLiteChoreCache`) with unit tests: least-recently-viewed eviction, account separation, erase-all, photo cap, photo pruning, bad rows skipped.
2. `ChoreDetailModel`: save after fetch, show saved copy first, refresh states, not-found removal, read-only when saved.
3. `ChoreDetailView`: banner, Refresh, disabled actions.
4. Photo download into the cache, and showing cached photos offline.
5. Home "Saved for offline" list.
6. Cold-launch "View saved chores" and notification taps; erase on sign-out and session expiry.
7. `-UITestOffline` launch argument, UI tests, specification.md section 5.2 note, `docs/phase-8-validation.md`.
