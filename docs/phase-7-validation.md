# Phase 7 validation — Favourite chores

Recorded 2026-09-24. Plan: [phase-7-favourites-plan.md](phase-7-favourites-plan.md).

## Backend

- Migration `202609240001_chore_templates.sql` (PapaBoard repo, **not yet committed there**) applied to the live project on 2026-09-24 with the user's approval. Only adds a table; no existing data touched.
- Verified after applying: RLS on, four policies (select/insert/update/delete for `authenticated`), `updated_at` trigger, freeze-`created_by` trigger, unique index on `lower(btrim(title))`.
- Live use: 2026-09-24 the user added two favourites from the app. A read-only count shows 2 rows from 1 creator. So create over RLS works on live.

## What was built

- **Data:** `ChoreTemplate` model, `ChoreTemplateRepository` (Supabase + fixture), `FavouritesStore` (shared list, people, save/delete/reorder with rollback), `FavouriteEditorModel`, pure `FavouriteRules`. New `DataServiceError.duplicate` (Postgres 23505) and `.notFound`.
- **Adding:**
  - chore detail `⋯` → **Save as Favourite** (title, description exactly as stored, assignee);
  - Settings → **Favourite Chores**: add, edit, swipe-to-delete with confirmation, and drag to reorder under Edit;
  - an empty state with a tip.
  - A title that is already taken offers **Replace It With This One**. Renaming a favourite onto another one merges the two.
- **Using:**
  - a favourites chip row on every new chore;
  - the **+** on Home: tap for a blank chore, touch and hold for the first 5 favourites;
  - title suggestions while typing, but only when no favourite is picked.
- **Switching (added after the first review, "option A"):**
  - The chip row stays visible for the whole create flow, and the favourite in use is highlighted with a checkmark.
  - Tapping another one swaps without asking if its title, description and assignee are untouched, and asks if they were changed.
  - Tapping the highlighted one again clears it.
  - Due date, status and photos are never replaced.
- A favourite with a web-made list is copied into the chore byte-for-byte (shown protected, with the usual "Edit as Text…").

### Differences from the plan

- `reorder([UUID])` became `updateSortOrders([UUID: Int])`: one small PATCH per moved row.
- The editor is its own `FavouriteEditorModel` rather than reusing `ChoreFormView` sections; it reuses `DescriptionEditorView` and `ProtectedDescriptionView`.
- The Home **+** uses a `Menu` with a primary action (tap = blank chore) instead of a `contextMenu`.
- The detail screen's favourites action is an explicit `⋯` menu. The system overflow placement (`.secondaryAction`) wasn't reliably reachable in UI tests.

## Automated evidence

Simulator: iPhone 18 Pro, iOS 27.0 (the app's minimum is 27.0, so the iOS 26.5 simulators can't run it).

| Check | Result |
|---|---|
| Build (`build-for-testing`) | Succeeded, no compiler warnings in app sources. |
| Full run, first version | 350 unit tests in 42 suites + 46 UI tests, all pass (`** TEST SUCCEEDED **`). |
| After option A: unit tests + affected UI tests | 355 unit tests pass; the 5 favourites UI tests that touch the form pass. |
| Full run after option A | 355 unit tests in 42 suites + 46 UI tests, all pass (`** TEST SUCCEEDED **`). |

New tests:
- `FavouritesTests.swift`: rules, form prefill, swap/clear, store, editor.
- `FavouriteBoundaryTests.swift`: request shape, 23505 → duplicate, zero-row update → not found, one PATCH per moved row. These run in the serialized stub suite.
- 8 UI tests:
  - chip fills, switches and saves;
  - the suggestion;
  - the confirm-before-replacing prompt;
  - the + long-press;
  - Save as Favourite from detail;
  - the duplicate-replace offer;
  - add, edit and delete in Settings;
  - the empty state.

Not automated: drag-to-reorder (unit-tested through the store and rules; UI drag is too flaky to be worth it). New launch argument: `-UITestNoFavourites`.

## Manual (pending, user)

Two-device smoke test on live:
1. Create a favourite "TEST - delete me" on one phone.
2. On the other phone, see it in Settings (pull to refresh) and use it in a new chore.
3. Switch it with another favourite, save, then delete the chore and the favourite.
