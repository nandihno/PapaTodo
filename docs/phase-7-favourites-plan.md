# Phase 7 plan — Favourite chores (shared templates)

Date: 2026-09-24. **Status: approved 2026-09-24. Migration applied to live the same day; app implemented. See docs/phase-7-validation.md.**

## Goal

Stop retyping chores you create again and again ("Go to Woolworths and see the list of items"). A favourite is a shared template: anyone in the family can add, edit, reorder or delete it, and anyone can use it. Using a favourite **pre-fills the New Chore form**; it never creates a chore on its own.

## Decisions (2026-09-24)

1. A favourite holds **title, description, and an optional default assignee** only. No due date rule, no photos, no status (new chores always start as Pending).
2. **Anyone can edit or delete** any favourite (same trust model as chore edits).
3. **iOS only.** The table lives in the shared backend, but PapaBoard web does not use it for now.
4. The "you've made this chore before — save as favourite?" nudge is **deferred** (not in this phase).

## UX

### Adding favourites
- **From a chore (primary path):** chore detail `⋯` (More) menu → **Save as Favourite**. A small sheet opens with the chore's title, description and assignee. You can edit them, then save. If a favourite with the same title already exists (case-insensitive), the sheet says so and offers **Update Existing**.
- **Settings → Favourite Chores:** a list of the shared favourites with a count.
  - **Add** opens the favourite editor (title, description, assignee).
  - Tap a row to edit it, swipe to delete (with confirmation), and use **Edit** to drag rows into a new order. The order is shared.
  - When the list is empty: "Tip: open any chore and choose Save as Favourite."

### Using favourites
- **New Chore form:** while the title is empty and nothing else has changed, a scrolling row of favourite chips sits above the title. Tapping one fills title, description and assignee. Typing in the title also shows matching favourites as suggestions.
- **Long-press the + on Home:** a menu with the first 5 favourites (in the shared order) plus "New Chore". Choosing one opens the form already filled in.
- Applying a favourite after you've typed something asks first ("Replace what you've entered?").
- The form is still an ordinary create: dates, status and photos are added as usual. The new chore has no link back to the favourite, so editing a favourite later changes nothing already created.

## Technical design

### Backend (PapaBoard repo)
`supabase/migrations/202609240001_chore_templates.sql` (applied to live 2026-09-24; still uncommitted in PapaBoard):
- `public.chore_templates(id, title, description, assigned_to → profiles on delete set null, sort_order, created_by default auth.uid(), created_at, updated_at)`.
- Title must be 1–200 characters after trimming, and is unique ignoring case and surrounding spaces.
- RLS: authenticated users can select, insert, update and delete (`true`), matching the family trust model.
- Triggers: the existing `set_updated_at`, plus the same freeze-`created_by` rule as `chores`.
- No Realtime: the list refreshes whenever Settings, the form, or the long-press menu loads it.

### iOS
- `Domain/Models/ChoreTemplate.swift` (`nonisolated`, Codable, snake_case keys) and a `ChoreTemplateDraft`.
- `Domain/Protocols/ChoreTemplateRepository.swift`: `fetchTemplates`, `create`, `update`, `delete`, `reorder([UUID])`. The Supabase version handles reorder by updating only rows whose position changed. There is also a fixture version for UI tests.
- `App/FavouritesStore.swift` (`@Observable @MainActor`): the loaded list, load/refresh, save/delete/move with the same save-state pattern as `ProfileStore`. It also maps a unique-title conflict (23505) to "A favourite with that name already exists."
- **Prefill:** `ChoreFormModel.Mode.create` gains an optional template. Applying a template:
  - sets title and assignee;
  - loads the description through `DescriptionEditing.load`. If that description is *protected* (lists or tables from the web), the raw stored string is kept and sent unchanged on save rather than flattened. This is the one tricky rule and gets explicit tests.
  - Prefilled values count as the form's baseline for `isDirty`, so opening a prefilled form and cancelling doesn't raise the discard prompt.
- **Views:** `Views/Favourites/FavouritesListView.swift` (Settings destination), `FavouriteEditorView.swift` (reuses the title, description and assignee sections from `ChoreFormView`), a chip row in `ChoreFormView`, the `⋯` menu item in `ChoreDetailView`, and a `contextMenu` on the Home `+`.
- `AppEnvironment` / `ChoreFormFactory` wire in the repository and store.

## Tests

- **Unit:**
  - applying a template fills the fields;
  - a protected description is saved byte-for-byte;
  - a prefilled form isn't dirty;
  - applying over edits asks first;
  - the reorder diff sends only rows that moved;
  - duplicate-title error mapping.
- **Repository:** decode, insert and update payloads, and the reorder requests, in the existing serialized `SupabaseServiceBoundaryTests` suite (shared `StubURLProtocol`).
- **UI (fixtures):**
  - save as favourite from detail;
  - add, edit, delete and reorder in Settings;
  - a chip fills the New Chore form and the chore saves;
  - the long-press menu opens a prefilled form;
  - the empty state.
- **Manual (live, by you):** create a favourite "TEST - delete me", use it on the other phone, create a chore from it, then delete both.

## Exit gate

1. You review and approve the migration, then it is applied to the live project (it only adds a new table, so it can't touch existing data).
2. The full `xcodebuild test` run passes and results are recorded in `docs/phase-7-validation.md`.
3. The manual two-device smoke test passes.
