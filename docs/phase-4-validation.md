# Phase 4 validation — Detail, status, comments, Realtime, and calendars

Date: 2026-09-20
Phase scope: specification.md section 14, "Phase 4 - Detail, status, comments, Realtime, and calendars"

**Status: code complete and verified on the simulator against fakes and a stubbed network. Exit gate NOT yet met:** the two-client comment check, web/iOS status consistency, and the physical-device EventKit check need you (steps below). Requested by the user after testing Phase 3 on a device and noticing the web app's detail view had photos, comments, Mark as Done and calendar buttons that native lacked.

## Files and behavior changed

- **Detail screen** (`Views/Detail/`): tapping a card now opens `ChoreDetailView` (as on the web) instead of the editor. It shows the hero photo and a strip of the others, title, a status button, the description (links tappable), assignee, creator, long due date, **Mark as Done**, **Save to Calendar** and **Google Calendar** (only when there is a due date), comments, and a pinned "Add a comment" bar. **Edit** is in the header and opens the Phase 3 form; deleting from there returns to the list.
- **Full-screen photos** (`PhotoViewerView`): swipe between photos, pinch to zoom, double-tap to reset, a 44pt close button, and "Photo n of m" VoiceOver labels.
- **Status:** tapping the badge cycles pending, in progress, done, pending. Changes wait for the server to confirm; a failure leaves the status alone and says why. Home is updated immediately (`HomeModel.upsert`), so the list never disagrees with the screen you just left.
- **Comments** (`ChoreDetailModel`, `CommentThread`): fetched oldest first with author names; a trimmed, non-empty body is required; the author is the signed-in user, read from the session. The list is a reducer keyed by comment id, so the insert response, the Realtime echo and a reload never produce duplicates. A failed send keeps the draft.
- **Realtime** (`SupabaseCommentRepository.changes`): a Postgres-changes channel scoped to one chore (`chore_id=eq.<id>`), started when the screen appears and closed when it goes away. If the connection drops the model reloads the comments (catching anything missed, with events that arrive during the reload buffered and re-applied) and resubscribes with backoff. Coming back to the foreground also reloads.
- **Calendar:** `CalendarEventDraft` (date-only = one-day all-day event with alerts 1 day before and on the day; timed = 30 minutes with alerts 2 hours and 30 minutes before; title, plain-text description and assignee), shown in the system "New Event" screen (`EventEditView`) so the user picks the calendar and confirms. Only an explicit save reports success; cancelling reports nothing. Denied and restricted calendar access are detected up front and reported (with an Open Settings button when denied). `GoogleCalendarURL` reproduces the web link exactly and opens in the browser.
- **Backend calls:** `updateStatus` (a single-row `status` update; the `updated_at` trigger does the rest), comment insert and fetch, and the Realtime subscription. The `chore_comments` table was added to the `supabase_realtime` publication on 2026-09-18, so live events are available.
- `Configuration/Info.plist` gains `NSCalendarsWriteOnlyAccessUsageDescription` as insurance; the app never prompts for calendar access itself.
- Search, fixtures and test hooks: fixed fixture chore ids and seeded comments, plus `-UITestRemoteComment`.

## Build and tests

- `xcodebuild ... build`: **BUILD SUCCEEDED** (Swift 6 mode).
- Full `xcodebuild test`, both targets: **TEST SUCCEEDED**. `PapaTodosTests`: **266 tests in 33 suites passed** (one skipped by design: the credentialed live read test). `PapaTodosUITests`: **30 tests, 0 failures**.
- New unit coverage: Google Calendar URLs and event text checked against PapaBoard's own JS output, event durations and reminders, comment thread reconciliation (duplicates, order, updates, deletes, arrival order), time-ago labels, the status cycle, the detail model (loading, sending, failure and retry, session expiry, double-tap, live insert/update/delete, dropped connection then reload and resubscribe, cancelling closes the subscription, a change racing a reload, status changes and their failures, calendar states), live request shapes for status and comments, and the Realtime row mapper.
- New UI coverage: opening the detail screen, the status cycle, Mark as Done moving the chore between tabs, comments (authors, validation, posting), a comment from another "device" appearing live exactly once, full-screen photos (open, swipe, thumbnail, close), Save to Calendar opening the system screen and cancelling without claiming success, no calendar buttons without a due date, edit and delete from the detail screen, and layouts at default and `AccessibilityXXXL` sizes.

## Exit gate

| Item | Status |
|---|---|
| Two clients observe comment changes without duplicates | **Met against fakes** (a change from another client arrives live and appears once, unit and UI). **Needs your two-device check** against the real Realtime service. |
| Status changes appear consistently in web and iOS | **Not yet checked live.** |
| Date-only and timed calendar events have correct duration and reminders | **Met in unit tests** and visually confirmed on the simulator (the system screen showed an all-day event with "On day of event" and "1 day before" alerts). Needs your check in the real Calendar app. |
| Permission denied and calendar save failure states are tested | **Met** for the states themselves (unit tests for denied, restricted, failed, cancelled, saved). The denied-access banner has not been exercised on a device. |
| Physical-device EventKit behavior is recorded | **Not yet.** |

## Your checks (about ten minutes)

1. **Photos:** open a chore with photos, tap the picture, swipe, pinch, close.
2. **Status:** tap the status badge through Pending, In progress, Done, and back; use Mark as Done on another; confirm the web app shows the same status.
3. **Comments, two devices:** open the same chore on your phone and in the web app. Post from the phone and see it appear on the web; post from the web and see it appear on the phone without pulling to refresh, exactly once.
4. **Calendar:** on a chore with a date only, tap Save to Calendar, pick a calendar, save, and check the event in the Calendar app (all-day, alerts day before and on the day). Repeat with a chore that has a time (30 minutes, alerts 2 hours and 30 minutes before). Also try cancelling.
5. **Google Calendar:** tap it and confirm the browser opens with the title, date and notes filled in.

## Known limitations and follow-up

- Notification dispatch after a status change or a comment belongs to Phase 5, so other family members are not pushed when you change status or comment from the phone.
- Comments can't be edited or deleted from the app (the web app doesn't offer it either).
- The system calendar screen is drawn out of process, so UI tests can only prove it appears and closes, not click inside it.
- Photo zoom uses a simple pinch gesture; very large photos load at full size.
