# Phase 3 validation — Chore editing, rich text, and attachments

Date: 2026-09-19
Phase scope: specification.md section 14, "Phase 3 - Chore editing, rich text, and attachments"

**Status: code complete and verified on the simulator against fakes and a stubbed network; basic create-with-photo and delete confirmed live by the user. Exit gate NOT fully met.** Open items: the rest of the live smoke test (edit, link, Paste, removing a photo), and a backend gap that makes "no Storage orphans" impossible on the live project until a policy is added.

## Product decisions (user, 2026-09-19)

1. **Rich text is links only.** The native editor edits text and links. This is the explicit product decision specification.md section 9.5 requires before reducing rich-text editing; it revises Phase 0 decision #6. Rendering still shows everything the web sanitizer allows.
2. **Existing formatting is protected.** A description with lists, tables, headings, emphasis, quotes or code is displayed as stored and is never rewritten by an unrelated edit. Editing it requires an explicit, confirmed "Edit as Text" choice that flattens it.
3. **Write testing:** fakes and a stubbed network for everything automated, plus one manual smoke test on the live project by the user.

Images keep full web parity, per the user's stated priority.

## Files and behavior changed

- **Description engine** (`Domain/Description/`): `DescriptionHTML` (allow-list parser and sanitizer mirroring PapaBoard's DOMPurify config; drops scripts, forms, frames, images, event handlers, inline styles, and any link that isn't absolute http/https/mailto/tel), `DescriptionFlattener` (lists, headings, blockquotes, code, rules and tables to readable styled text) and `DescriptionDisplay` (read-only text with tappable links), `DescriptionEditing` (links-only editor conversion, protected-description detection, and storage: plain text when there are no links, sanitized `<p>/<br>/<a>` HTML when there are; plain text that would look like HTML to the web is stored escaped).
- **Write path:** `ChorePatch` (only changed fields are sent; `nil` = unchanged, `.some(nil)` = clear), `ChoreSaveService` (upload, create/update, attachment rows, row deletes, file removal, each with compensation; only undoes what the save itself created), `ChoreDeleteService`, `DueDateForm` (date and optional time with the legacy local-noon sentinel).
- **Live services:** `SupabaseChoreRepository` writes (creator read from the session, never from the caller; `created_by` never sent on update), `SupabaseAttachmentRepository`, `SupabaseAttachmentStorage` (path `{userId}/{timestamp}-{uuid}-{filename}`), and a 403/42501 to `.notPermitted` mapping.
- **Photos:** `ImageProcessing` (image validation; HEIC/other formats to JPEG because browsers can't show HEIC; longest side capped at 2048px; EXIF orientation applied; location and other metadata not carried over; GIF/WebP untouched; PapaBoard's filename sanitizer).
- **UI:** `ChoreFormView` (new/edit as a sheet from Home: title with validation, description editor with Add/Remove Link, assignee, status, due date and optional time, photo previews with remove, multi-select PhotosPicker and Paste button, confirmed delete, discard confirmation, duplicate-submit guard, draft preserved on failure), `ProtectedDescriptionView`, `DescriptionEditorView`, `PhotosSectionView`. Home gains a "+" button; **tapping a card now opens the edit form** (Phase 4 will open a detail screen instead). Home shows a dismissible note when a save or delete finished with a caveat.
- Search now reads the visible text of HTML descriptions rather than the markup.

## Build and tests

- `xcodebuild ... build`: **BUILD SUCCEEDED** (Swift 6 mode).
- Full `xcodebuild test`, both targets: **TEST SUCCEEDED**.
  - `PapaTodosTests`: **218 tests in 29 suites passed** (one skipped by design: the credentialed live read test).
  - `PapaTodosUITests`: **20 tests, 0 failures**.
- New unit coverage: description parser/sanitizer (XSS vectors, `javascript:` obfuscation, entities, malformed input), flattening of every allowed structure, links-only editing round trips and protected-description rules, the save/delete orchestration under injected failure at every step (`ChoreSaveServiceTests`), live request shapes against a signed-in stubbed client (`LiveWriteBoundaryTests`), image processing (`ImageProcessingTests`), due-date round trips across five time zones and a year of dates (`DueDateFormTests`), and the form model (`ChoreFormModelTests`).
- New UI coverage: required title, create, edit, confirmed delete, discard confirmation, photo preview/remove/save, link insert and unsafe-link rejection, protected description surviving an unrelated edit, search inside structured descriptions, and form layouts at default and `AccessibilityXXXL` sizes.

## Exit gate

| Item | Status |
|---|---|
| Create/edit/delete succeeds under RLS on an approved test environment | **Partly met.** User reported create (assigned to self) with a photo and delete working live; edit was not reported. |
| Date-only and timed values round-trip without drift | **Met** in unit tests (five zones, a year of days, minute-level times; untouched due dates are never re-sent, so sub-second stored values are preserved). |
| Existing rich descriptions render and unrelated edits don't destroy markup | **Met** in unit and UI tests. |
| Multi-photo upload/remove/gallery ordering matches the web client | **Met against fakes** (same `sort_order` rule, primary-image and legacy `image_url` handling). The full-screen gallery is Phase 4. |
| Injected failures leave no known new Storage or database orphans | **Met against fakes; not achievable on the live project today** (see backend finding). Leftover files are reported to the user, not hidden. |
| Physical device verifies PhotosPicker and copied-image handling | **Partly met.** A photo was added on device (user-reported, presumably via the picker); copied-image Paste not reported. |

## Backend findings (read-only audit, 2026-09-19; nothing changed or deployed)

1. **`chore-images` has no DELETE policy.** `storage.objects` allows only INSERT and SELECT for that bucket, so removing files is silently refused (Storage returns an empty list, no error). PapaBoard's own cleanup has the same problem, so photo files are orphaned on delete and on failed saves today. The app detects this by comparing what was removed with what was requested, and tells the user ("N photo files are still in storage and can't be removed yet"); the message will appear on every photo removal until the policy exists. **Proposed fix, for the PapaBoard repo, not applied (needs your authorization):**

   ```sql
   -- Let a signed-in user delete the chore images they uploaded (their own {userId}/ prefix).
   create policy "Users can delete their own chore images"
   on storage.objects for delete to authenticated
   using (bucket_id = 'chore-images' and (storage.foldername(name))[1] = auth.uid()::text);
   ```
   **Prepared, not applied (2026-09-20):** the migration is written as `supabase/migrations/202609200001_allow_chore_image_delete.sql` in the PapaBoard repo (uncommitted there, alongside the user's own uncommitted work). It needs the user's review and authorization before it is applied.

   **Scale of the existing problem (read-only count, 2026-09-20):** 36 of the 38 files in `chore-images` are not referenced by any attachment row or chore. The policy only stops new orphans; the existing ones need a one-off cleanup through the Storage API (dashboard or a script), because deleting `storage.objects` rows by SQL leaves the underlying files behind.

   Trade-off: it cannot remove files another family member uploaded (for example an assignee deleting a creator's photo); those would still be left behind. Files already orphaned would need a one-off cleanup.
2. **Attachment rows are properly scoped:** only a chore's creator or assignee can add or delete photos; anyone signed in can still edit the chore's text. The app maps the refusal to a clear message and rolls back what the save created.
3. **`chores` INSERT has `with check (true)` and no `created_by` default**, so the creator is not enforced by the database. The app sets it from the session on create and never sends it on update.
4. Comments and attachment rows are removed by `ON DELETE CASCADE` when a chore is deleted.

## Live smoke test result (user-reported, 2026-09-20)

On a physical device against the live project the user reported: created a new chore assigned to themselves, added a photo, and deleted the chore. All three worked. Reported by the user, not observed from this session.

On delete the user saw the note "Chore deleted. 1 photo file is still in storage and can't be removed yet." (screenshot shared). **This confirms backend finding 1 on the live project:** the bucket refused the file delete, the app detected it by comparing what was removed with what was requested, and reported it instead of hiding it. The test photo's file is therefore still in the public `chore-images` bucket and needs a one-off cleanup once a DELETE policy exists (or manual removal in the Supabase dashboard).

**Not yet reported:** adding a link to the description; multiple photos; Paste from the clipboard; editing an existing chore (title only, checking that the description and due date stay unchanged); and removing a single photo on save. The create and delete under live RLS gate item is therefore met for the basic path only.

## Live smoke test (steps)

Use a chore titled "TEST - delete me", on your device, with a build from this commit:

1. Create it with a title and a link in the description (select text, Add Link).
2. Add two photos with Choose Photos, and one via a copied image and Paste.
3. Save, and confirm it appears and the photos count shows 3.
4. Edit it: change the title only, save, and confirm the description and due date are unchanged.
5. Remove one photo and save. Expect the note about a file still in storage (until the policy exists).
6. Delete it, confirm, and check it disappears from the list (and from PapaBoard).

Then report what you saw and I'll record it here.

## Known limitations and follow-up

- Notification dispatch after save (spec step 6) belongs to Phase 5.
- Tables render as rows of text, not a grid; there is no full-screen photo viewer until Phase 4.
- Cards open the editor for now; the detail screen replaces that in Phase 4.
- No camera capture (not in the spec); paste and the photo library cover the web's flows.
- Real token-refresh and offline behavior of the write path against the live server is covered by mapping tests, not observed live.
