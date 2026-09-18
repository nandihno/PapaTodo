# PapaTodos native iOS specification

Version: 1.0 planning baseline

Prepared: 2026-09-18, Australia/Melbourne

Status: Planning only. The native application, shared-backend changes, APNs delivery, device validation, and release qualification are not implemented by this document.

Estimated delivery: 29-41 engineering days for one experienced iOS/Supabase developer. Allow 7-9 calendar weeks for implementation, validation, UAT, and contingency.

## 1. Purpose

PapaTodos is the native iOS client for the existing PapaBoard family chore system. It must use the same Supabase project and preserve the web application's current behavior while replacing browser-specific interaction patterns with native SwiftUI equivalents.

The first release is for the existing private family use case. The plan deliberately avoids redesigning the backend, adding unrelated collaboration features, or treating an Xcode build as proof that end-to-end behavior works.

## 2. Product objective

Deliver a native application that lets an authenticated family member:

1. Sign in with the existing Supabase email/password account.
2. View chores assigned to them, all active chores, and completed chores.
3. Search chores and see the same due-date ordering and status semantics as the web client.
4. Create, edit, assign, complete, reopen, and delete chores.
5. Preserve rich descriptions and existing HTML-backed description content.
6. Add, view, and remove multiple photo attachments.
7. Read and add realtime comments.
8. Save a chore to Apple Calendar and open the Google Calendar handoff.
9. Use the existing profile name, avatar URL, and chosen theme color.
10. Receive native APNs notifications for the same events currently sent through Web Push.
11. Open the relevant chore when a notification is tapped.

The web and iOS applications must be able to operate concurrently against the same data.

## 3. Repository and deployment boundaries

### 3.1 Native client repository

Native application work belongs in:

```text
/Users/fernandodeleon/dev/IOSDevelopment/PapaTodos
```

This repository owns:

- the Xcode project and Swift source;
- native configuration that is safe to ship in the client;
- Swift Package Manager dependency declarations;
- unit and UI tests;
- native assets, entitlements, and privacy declarations;
- native validation records and release documentation.

### 3.2 Shared backend repository

Shared Supabase infrastructure currently belongs in:

```text
/Users/fernandodeleon/dev/NandoProjects/PapaBoard
```

That repository remains the canonical owner of:

- Supabase SQL migrations;
- Row Level Security policies;
- Storage policies and bucket assumptions;
- the `send-push` Edge Function;
- Web Push support;
- shared notification event and recipient rules.

Do not copy backend migrations into both repositories. Every backend change needed by iOS must be implemented and reviewed in the backend-owning repository, then referenced from PapaTodos validation documentation.

### 3.3 Deployment boundary

Local implementation does not imply deployment. The following are separate states and must be reported separately:

1. specification written;
2. native code implemented locally;
3. native build succeeded;
4. test bundles compiled;
5. simulator tests executed;
6. Supabase migration reviewed;
7. Supabase migration deployed;
8. Edge Function deployed;
9. APNs accepted a request;
10. a physical device received and opened the notification;
11. TestFlight build uploaded;
12. family UAT passed;
13. production release approved.

## 4. Observed baseline

### 4.1 PapaTodos checkout

Observed on 2026-09-18:

- The destination contains a generated SwiftUI starter application.
- `ContentView.swift` still displays the template `Hello, world!` content.
- The project has one application target and no unit-test or UI-test targets.
- No external package dependencies are configured.
- The project deployment target is iOS/iPadOS 27.0.
- The project currently targets both iPhone and iPad device families.
- The project file declares Swift language version 5.0.
- The bundle identifier is `org.nando.PapaTodos`.
- Automatic signing is enabled.
- The directory is not currently a Git repository.
- The project name, PapaTodos, differs from the existing product name, PapaBoard.

Phase 0 must reconcile these settings before feature code is added. Until then, the delivery estimate assumes iOS 27.0 and later, an iPhone-first interface, and basic buildable iPad compatibility without a separate tablet information architecture.

### 4.2 PapaBoard functional reference

The current PapaBoard web source is the behavioral reference. Its relevant capabilities are:

- Supabase email/password authentication and session refresh;
- profile loading and sign-out;
- Mine, All, and Done chore tabs;
- title, description, person, and status search;
- due-date sorting, including today, overdue, future, and no-date chores;
- chore creation, editing, deletion, assignment, status, due date, and optional due time;
- sanitised rich-text descriptions;
- multiple photo attachments in the public `chore-images` bucket;
- chore detail, full-screen images, status updates, and comments;
- Realtime subscription to comment changes;
- `.ics` calendar export and Google Calendar URL handoff;
- profile theme color and avatar URL;
- Web Push for assignment, update, comment, and status events;
- a `due-soon` event shape without a live scheduler.

The PapaBoard working tree was not clean when this plan was prepared. It contained active Home screen changes and an untracked iOS notification-device migration. Phase 0 must select and record the exact source snapshot used as the parity baseline without overwriting that work.

### 4.3 Existing native-notification groundwork

The backend checkout contains a draft migration named:

```text
supabase/migrations/202607150001_ios_notification_devices.sql
```

It proposes:

- a `notification_devices` table;
- user-scoped RLS;
- sandbox/production APNs environment separation;
- bundle identifier and device-token uniqueness;
- authenticated register/unregister RPCs;
- an `updated_at` trigger.

This is useful groundwork, but it is currently an untracked local file. Its presence does not prove that it has been reviewed, committed, applied, or deployed.

The current `send-push` function still reads only `push_subscriptions` and calls the Web Push provider. Native delivery therefore requires a new APNs provider path, not just device-token registration.

## 5. Scope boundaries

### 5.1 Included in version 1

- Native SwiftUI interface.
- Existing Supabase email/password accounts.
- Shared production data with the web client.
- Existing chore, profile, comment, and attachment behavior.
- Native photo selection and copied-image paste.
- Existing rich-description content and equivalent editing behavior.
- Native calendar creation and Google Calendar handoff.
- Realtime comments.
- Native APNs notifications for current event types.
- Notification permission and enable/disable state.
- Notification tap routing to chore detail.
- Dynamic Type, VoiceOver, keyboard, contrast, and reduced-motion consideration.
- Unit, integration-boundary, and UI tests appropriate to each phase.
- Physical-device validation for capabilities that cannot be proven in the simulator.
- TestFlight/UAT preparation.

### 5.2 Explicitly excluded from version 1

- Android.
- Replacement or retirement of the web client.
- A WebView wrapper around the existing site.
- Offline-first editing, conflict resolution, or a durable offline write queue.
- New account registration, invitations, password-reset UX, or family administration.
- Sign in with Apple unless separately requested.
- A redesigned backend or a new API server.
- CloudKit or SwiftData as an alternative system of record.
- Widgets, App Intents, Siri, Share extensions, Live Activities, or Apple Watch.
- Arbitrary frontend-selected notification recipients.
- Silent-push background synchronization.
- A scheduled `due-soon` reminder service.
- An iPad-specific split-view design.
- A new avatar upload flow; version 1 preserves the existing avatar-URL behavior.

### 5.3 Optional later scope

- Server-scheduled due-soon reminders: add approximately 3-5 engineering days.
- Offline-first reads and writes: add approximately 1-2 weeks plus conflict-policy decisions.
- Fully optimized iPad interface: add approximately 3-5 engineering days.
- Camera capture, cropping, compression controls, or attachment reordering beyond web parity.
- Account onboarding and family membership management.

## 6. Shared data contract

Phase 0 must verify the live schema rather than infer it solely from frontend queries. The repository does not contain the full creation history for every original table and policy.

### 6.1 Profiles

Required fields:

| Field | Purpose |
|---|---|
| `id` | Supabase Auth user identifier and profile primary key |
| `full_name` | Display and assignment name |
| `avatar_url` | Optional HTTP/HTTPS avatar URL |
| `personalisation` | JSON containing the profile theme color |

The native client may update only the authenticated user's permitted profile settings.

### 6.2 Chores

Required fields:

| Field | Purpose |
|---|---|
| `id` | Stable chore UUID |
| `title` | Required chore title |
| `description` | Optional plain text or sanitised HTML |
| `assigned_to` | Optional profile UUID |
| `created_by` | Creator profile UUID |
| `status` | `pending`, `in_progress`, or `done` |
| `due_date` | Optional timestamp preserving date-only sentinel semantics |
| `image_url` | Legacy/primary image compatibility field |
| `created_at` | Creation ordering and display support |
| `updated_at` | Latest update time |

### 6.3 Date-only and timed chore semantics

The existing system stores date-only chores using local noon as a legacy sentinel. Native code must preserve this distinction:

- no due date: `due_date = null`;
- date-only: local-noon sentinel converted to the stored timestamp;
- timed: the selected local date/time converted to an absolute timestamp;
- date-only calendar event: one-day all-day event;
- timed calendar event: 30-minute event;
- timed alerts: two hours and 30 minutes before;
- date-only alerts: one day before and on the day.

Parsing, display, editing, sorting, calendar creation, and round-trip tests must all use the same rule. Do not infer date-only status merely from an arbitrary displayed time.

### 6.4 Chore attachments

Required fields:

| Field | Purpose |
|---|---|
| `id` | Stable attachment UUID |
| `chore_id` | Parent chore |
| `storage_path` | Object path in `chore-images` |
| `public_url` | Existing public display URL |
| `file_name` | Original/sanitised file name |
| `mime_type` | Uploaded media type |
| `sort_order` | Stable gallery order |
| `created_by` | Uploading profile |
| `created_at` | Stable secondary order |

Keep the existing storage path convention:

```text
{userId}/{timestamp}-{uuid}-{sanitisedFilename}
```

Retain compatibility with chores that have only the legacy `image_url` field.

### 6.5 Comments

Required fields:

| Field | Purpose |
|---|---|
| `id` | Stable comment UUID |
| `chore_id` | Parent chore |
| `author_id` | Author profile |
| `body` | Required trimmed text |
| `created_at` | Chronological ordering |

Comment Realtime must be scoped to the selected chore and must unsubscribe when the detail flow ends.

### 6.6 Notification records

Web Push subscriptions remain in `push_subscriptions`. Native APNs tokens belong in `notification_devices`. `notification_deliveries` remains the durable de-duplication ledger only for event types that require de-duplication.

Do not de-duplicate comments, ordinary status changes, or repeated edits unless product behavior is intentionally changed. Do not let a frontend specify arbitrary recipient UUIDs; recipients must continue to be derived from the authenticated caller and chore record.

## 7. Native architecture

### 7.1 Technology baseline

- SwiftUI for screens and native navigation.
- Observation-based state with `@Observable` models/stores where shared mutable state is required.
- `@MainActor` for UI-bound observable state.
- Swift concurrency with structured `async`/`await`.
- Codable, Sendable value models for Supabase records crossing concurrency boundaries.
- Supabase Swift through Swift Package Manager.
- `NavigationStack` for detail/edit navigation.
- `PhotosPicker` plus a small pasteboard adapter for attachments.
- EventKit for native Apple Calendar creation.
- `UNUserNotificationCenter` and APNs for native notifications.
- Swift Testing or XCTest for logic, plus XCUITest for journeys.

Phase 0 must select and pin an exact reviewed Supabase Swift release rather than leaving an unbounded floating dependency. The official package exposes the `Supabase` product and supports Auth, database queries, Storage, Edge Functions, and Realtime.

### 7.2 Model-view approach

Use a small model-view architecture:

- Views express state and user actions.
- Domain rules live in pure models/services.
- Supabase access is isolated behind narrow clients/repositories.
- Shared session and routing state may use `@Observable` stores injected through the environment.
- Do not create a view model for every view by default.
- Use `.task` and `.task(id:)` for cancellable view-bound loading.
- Keep filtering, sorting, date semantics, and compensation logic out of SwiftUI `body` implementations.

### 7.3 Suggested source organization

```text
PapaTodos/
  App/
    PapaTodosApp.swift
    AppEnvironment.swift
    AppRouter.swift
    AppSession.swift
  Configuration/
    AppConfiguration.swift
  Domain/
    Models/
    Rules/
    Protocols/
  Features/
    Authentication/
    Home/
    ChoreEditor/
    ChoreDetail/
    Settings/
  Services/
    Supabase/
    Attachments/
    Calendar/
    Notifications/
  DesignSystem/
  Resources/
PapaTodosTests/
PapaTodosUITests/
docs/
```

The final structure may vary, but domain rules, backend access, and screen composition must remain separable and testable.

### 7.4 Proposed core protocols

```swift
protocol Authenticating: Sendable {
    func currentSession() async throws -> AppSessionRecord?
    func signIn(email: String, password: String) async throws
    func signOut() async throws
}

protocol ChoreRepository: Sendable {
    func fetchChores() async throws -> [Chore]
    func fetchChore(id: UUID) async throws -> Chore?
    func create(_ draft: ChoreDraft) async throws -> Chore
    func update(id: UUID, draft: ChoreDraft) async throws -> Chore
    func updateStatus(id: UUID, status: ChoreStatus) async throws
    func delete(id: UUID) async throws
}

protocol CommentRepository: Sendable {
    func fetchComments(choreID: UUID) async throws -> [ChoreComment]
    func addComment(choreID: UUID, body: String) async throws
    func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error>
}
```

Tests must be able to substitute deterministic fakes without requiring production Supabase access.

## 8. Configuration and secret handling

### 8.1 Client configuration

The native client needs:

- Supabase project URL;
- Supabase publishable/anon key;
- bundle identifier;
- an environment identifier used for APNs token registration.

Use build configuration or generated configuration values. Do not hardcode environment-specific values throughout source files.

The Supabase publishable/anon key is designed for client use, but access control must still come from RLS. Never place the Supabase service-role key, APNs private key, Web Push VAPID private key, or other server credentials in the application bundle.

### 8.2 Server secrets

The Edge Function will require server-side APNs credentials, such as:

- Apple team identifier;
- APNs key identifier;
- APNs private signing key;
- allowed PapaTodos bundle identifier/topic.

These must be stored as Supabase secrets or another approved secret store and must never be printed in logs or committed.

### 8.3 Source control foundation

Phase 0 must:

- decide whether PapaTodos becomes its own Git repository or joins an existing parent repository;
- add a suitable `.gitignore` before generating local signing/configuration artifacts;
- exclude local configuration, credentials, DerivedData, and user-specific Xcode state;
- establish a clean initial baseline before feature implementation.

## 9. User experience requirements

### 9.1 Authentication

- Show email and password fields with appropriate keyboard/content types.
- Restore a valid saved session on launch.
- Observe authentication changes.
- Refresh expired sessions through the SDK-supported session flow.
- Return to sign-in with a clear message when authentication cannot be recovered.
- Keep credentials and session tokens in SDK-supported secure storage.
- On sign-out, unregister the current APNs token on a best-effort basis before clearing the session; sign-out must still complete if unregistering fails.
- Do not include signup or password reset in version 1.

### 9.2 Home

Provide three filters:

- **Mine:** active chores assigned to the current user;
- **All:** all active family chores;
- **Done:** completed family chores.

Search across:

- title;
- description converted to plain text;
- assignee name;
- creator name;
- human-readable status.

Sort chores in this order:

1. due today;
2. overdue, with the most recently overdue first as in the current web rule;
3. future due dates in ascending order;
4. no due date;
5. newest creation as the final tie-breaker.

Support initial loading, pull-to-refresh, foreground refresh, empty states, errors, and retry. A foreground return must not allow an older request to overwrite a newer result.

### 9.3 Chore card

Show:

- title;
- status;
- assignee avatar/initials and name;
- due label and semantic overdue/today/upcoming/done state;
- primary photo thumbnail;
- attachment count when greater than one.

Information must not rely on color alone.

### 9.4 Create and edit chore

Fields:

- required title;
- optional rich description;
- assignee;
- optional due date;
- optional due time enabled only when a due date exists;
- status;
- zero or more photo attachments.

Editing must load the current record and attachments. Saving must preserve the authenticated creator and enforce RLS rather than trusting client-supplied ownership.

### 9.5 Rich descriptions

The backend contains both plain text and an allowed subset of HTML. Version 1 must:

- render existing plain text and HTML safely;
- preserve paragraphs, line breaks, emphasis, links, lists, headings, blockquotes, code/preformatted text, horizontal rules, and basic tables used by the web sanitizer;
- reject or remove scripts, forms, embedded objects, remote inline images, unsafe URLs, and unsupported styling;
- provide a native editing surface, likely a focused TextKit/`UITextView` bridge where SwiftUI alone cannot preserve required formatting;
- test HTML-to-display and edit-to-storage round trips with representative fixtures;
- avoid silently destroying existing markup when a user edits an unrelated chore field.

If exact rich-text editing is later reduced to plain text, that must be an explicit product decision and the estimate can be reduced by approximately 2-3 days.

### 9.6 Attachment workflow

- Select multiple images from the system photo picker.
- Add a copied image from the pasteboard when available.
- Preview newly selected images before save.
- Remove pending and existing images.
- Preserve stable attachment order.
- Show a gallery and full-screen viewer in chore detail.
- Upload using the authenticated user's storage prefix.
- Keep `image_url` synchronized to the first remaining attachment for legacy compatibility.

The multi-resource save is not atomic. Implement explicit compensation:

1. upload new Storage objects;
2. create or update the chore;
3. insert attachment rows;
4. remove deleted attachment rows;
5. remove deleted Storage objects;
6. invoke the notification event without blocking the successful chore operation.

On failure, remove newly uploaded orphan objects and roll back newly inserted attachment rows where safe. Never delete a pre-existing user attachment while compensating for a failed new upload.

### 9.7 Chore detail and status

- Show title, description, photos, assignee, creator, due date/time, and current status.
- Allow the existing status cycle: pending -> in progress -> done -> pending.
- Provide an explicit Mark as Done action while incomplete.
- Open the editor for the selected chore.
- Optimistically update status only when rollback/error behavior is clear; otherwise wait for confirmed backend success.
- Dispatch status notification as a non-blocking secondary operation after the database write succeeds.

### 9.8 Comments and Realtime

- Fetch comments oldest first with author profiles.
- Validate trimmed non-empty bodies.
- Insert as the authenticated user.
- Subscribe to inserts, updates, and deletes for the selected chore.
- Reconcile received events without duplicates.
- Cancel the channel/task when leaving the chore.
- Reconnect or reload after foregrounding if the subscription was interrupted.
- A notification failure must not make comment submission fail.

### 9.9 Calendar

For Apple Calendar:

- use EventKit and a user-initiated permission request;
- let the user select/confirm the destination calendar through the native flow;
- create a one-day all-day event for date-only chores;
- create a 30-minute timed event for timed chores;
- include the chore title, plain-text description, and assignee;
- add the existing reminder offsets;
- show clear permission-denied and save-failure states;
- never claim success from permission alone; verify the event save returned successfully.

For Google Calendar:

- preserve the URL handoff with title, local date/time range, description, and timezone;
- use the system browser/open-URL flow.

### 9.10 Settings and personalization

- Show the profile name and email.
- Render the current avatar URL or initials fallback.
- Validate avatar URLs as HTTP/HTTPS before saving.
- Allow clearing the avatar URL.
- Load, preview, and save the profile theme color.
- Apply an accessible foreground color and avoid using the theme as the only status signal.
- Show notification authorization and registration state.
- Offer an Open Settings action after notification permission has been denied.
- Sign out.

The product decision about whether the notification control remains on Home, moves to Settings, or appears in both places must be resolved in Phase 0. Capability and behavior matter more than preserving the exact web placement.

## 10. Native notification design

### 10.1 Client registration

The app must:

1. explain notification value before the system prompt;
2. request alert, badge, and sound permission from a user action;
3. register with `UIApplication` for remote notifications only after permission is granted;
4. receive the device token through an application delegate adaptor;
5. convert the token to lowercase hexadecimal;
6. call the authenticated `register_notification_device` RPC with token, bundle identifier, and APNs environment;
7. resend registration whenever APNs supplies a token because tokens can change;
8. unregister on explicit disable/sign-out when possible;
9. handle denied permission by linking to system Settings;
10. never log a full token in production diagnostics.

Debug/sandbox and TestFlight/App Store production tokens must not be mixed.

### 10.2 Backend delivery

Extend the existing notification operation so it:

- authenticates the caller exactly as the current function does;
- derives recipients from the chore and caller;
- builds one canonical notification intent;
- queries both Web Push subscriptions and native notification devices;
- delivers Web Push without regression;
- creates an APNs JWT on the server and sends an HTTP/2 request to the correct APNs host/topic;
- includes the `choreId`, event type, and a native route value in the payload;
- records per-channel success/failure without exposing credentials;
- removes invalid/expired Web Push subscriptions on 404/410;
- removes invalid/unregistered APNs tokens based on APNs terminal responses;
- does not fail a successful chore/comment/status mutation merely because notification delivery fails;
- preserves delivery-key semantics for assignment and any future scheduled reminder.

A successful Edge Function response means the provider request completed; it does not prove that a device displayed the notification. Physical-device receipt and tap handling require separate evidence.

### 10.3 Foreground and tap behavior

- Define foreground presentation behavior explicitly.
- Route a notification tap to the referenced chore.
- If authentication restoration is still in progress, retain the pending route and consume it after sign-in succeeds.
- If the chore no longer exists or is inaccessible, show a safe not-found state rather than an empty screen or crash.
- Do not include sensitive description/comment content in the notification payload.

### 10.4 Current event matrix

| Event | Recipient rule | Delivery key |
|---|---|---|
| `chore-assigned` | Assignee excluding caller | De-duplicated per chore and assignee |
| `chore-updated` | Creator and assignee excluding caller | No de-duplication |
| `comment-created` | Creator and assignee excluding caller | No de-duplication |
| `status-changed` | Creator and assignee excluding caller | No de-duplication |
| `due-soon` | Assignee | Shape exists, scheduler excluded from version 1 |

## 11. Security and reliability requirements

### 11.1 RLS and authorization audit

Before connecting feature screens to production data, verify and record:

- authenticated read scope for profiles;
- who may read each chore;
- who may create, update, change status, and delete chores;
- who may read/add/delete comments;
- who may read/add/delete attachment rows;
- Storage object insert/read/delete policies for `chore-images`;
- notification device user ownership;
- Edge Function recipient derivation and caller authorization.

Use read-only inspection first. Any policy change must be additive/reviewable, tested in a non-production environment where available, and deployed only with explicit authorization.

### 11.2 Error behavior

- Present actionable errors without leaking raw credentials, tokens, or internal policy detail.
- Preserve the user's draft after a recoverable save error.
- Prevent duplicate submissions while a write is in flight.
- Cancel obsolete loads and ignore late responses.
- Make notification dispatch non-blocking.
- Make attachment cleanup observable and retryable when partial failure occurs.
- Do not label an upload acknowledgement, provider acceptance, or successful build as end-to-end success.

### 11.3 Logging

Use privacy-aware structured diagnostics for:

- authentication lifecycle category;
- database operation type and outcome;
- Realtime lifecycle;
- attachment compensation outcome;
- notification registration and provider result category;
- calendar permission/save outcome.

Never log passwords, access/refresh tokens, service-role keys, APNs signing material, full device tokens, or comment/description bodies.

## 12. Accessibility and design requirements

- Prefer native controls, navigation, sheets, alerts, menus, pickers, and system materials.
- Support Dynamic Type through accessibility sizes without clipped actions.
- Provide useful VoiceOver labels, values, traits, and ordered focus.
- Maintain at least 44x44-point interactive targets.
- Do not encode status or overdue state using color alone.
- Support light and dark appearances.
- Respect Reduce Motion and Reduce Transparency.
- Use semantic colors and text styles.
- Keep loading placeholders non-distracting and accessible.
- Ensure photo controls have meaningful labels that do not announce decorative images twice.
- Provide accessible alternatives for custom rich-text editing controls.
- Test portrait and landscape on representative iPhone sizes; verify the universal build on iPad even though no iPad-specific design is planned.

## 13. Testing strategy

### 13.1 Unit tests

At minimum, cover:

- chore status decoding and transitions;
- Mine/All/Done filtering;
- search normalization and HTML-to-plain-text behavior;
- due-date sorting;
- date-only sentinel round trip;
- due labels around day boundaries and timed overdue behavior;
- calendar event duration and reminders;
- attachment sorting and legacy `image_url` fallback;
- filename/path sanitization;
- rich-description sanitization and round trip;
- recipient and delivery-key rules represented in shared fixtures;
- pending deep-link routing after session restoration.

### 13.2 Repository/service tests

Use fakes for deterministic client tests. Add targeted integration tests against an approved local/staging Supabase environment for:

- auth session behavior;
- relational chore/profile/attachment decoding;
- RLS-allowed and RLS-denied operations;
- Storage upload and removal;
- comment Realtime lifecycle;
- device registration RPC behavior;
- Edge Function request authentication and recipient enforcement.

Do not run destructive integration tests against production family data.

### 13.3 UI tests

Cover at least:

- launch into signed-out state;
- successful fixture/fake sign-in journey;
- switch Mine/All/Done;
- search and clear search;
- open detail and edit;
- create validation;
- status change;
- add a comment;
- settings/theme/avatar validation;
- authentication-expired recovery;
- pending notification route consumption through an injected launch route.

Live APNs, Photos, pasteboard, EventKit, and Supabase production behavior are physical-device/UAT checks, not substitutes for deterministic UI tests.

### 13.4 Build and test commands

Phase 0 must verify the actual scheme and destinations with `xcodebuild -list` and `xcodebuild -showdestinations`. Use an explicit writable DerivedData path in restricted environments. The expected command shapes are:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build-for-testing \
  -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=<verified-simulator-id>' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project PapaTodos.xcodeproj \
  -scheme PapaTodos \
  -destination 'platform=iOS Simulator,id=<verified-simulator-id>' \
  -derivedDataPath /private/tmp/PapaTodos-derived \
  CODE_SIGNING_ALLOWED=NO
```

These are planned command forms, not checks completed by this specification. A successful `build-for-testing` proves compilation/wiring only; it does not prove that tests executed.

### 13.5 Phase evidence

Each implemented phase must add or update:

```text
docs/phase-N-validation.md
```

Record:

- files and behavior changed;
- build command and result;
- test compilation result;
- tests actually executed and result;
- simulator journeys executed;
- physical-device checks executed;
- backend changes reviewed/deployed;
- known limitations and follow-up work.

## 14. Development phases and exit gates

Only one requested phase should be implemented at a time. Re-read this specification, applicable AGENTS guidance, current Kiro steering, and both relevant working trees before each phase. Preserve unrelated user changes and do not silently advance to a later phase.

### Phase 0 - Foundation and contract audit (3-4 days)

Work:

1. Decide the user-facing name: PapaTodos or PapaBoard.
2. Decide source-control placement and establish a clean baseline.
3. Confirm iOS 27.0 minimum and iPhone-first/basic-iPad scope, or explicitly revise them.
4. Select Swift language/concurrency settings supported by the installed Xcode and SDK.
5. Add unit and UI test targets and a shared scheme.
6. Add repo-local `AGENTS.md`, README status, and validation template.
7. Add and pin Supabase Swift through Swift Package Manager.
8. Create typed configuration loading without server secrets.
9. Establish app/session/router composition and deterministic fixture clients.
10. Define Codable/Sendable domain contracts and due-date rules.
11. Audit the live Supabase schema, RLS, Storage, Realtime publication, deployed functions, and migration state using read-only checks.
12. Freeze a feature-parity checklist against an exact PapaBoard source snapshot.
13. Build and compile test bundles.

Exit gate:

- Clean build succeeds.
- Unit/UI test bundles compile.
- At least one deterministic test executes on a functioning simulator.
- No production data mutation or backend deployment was required.
- Product-name, platform-floor, device-family, and repository decisions are recorded.
- Live backend observations and unknowns are documented without exposing secrets.

### Phase 1 - Authentication and shared data services (3-4 days)

Work:

1. Implement Supabase client composition.
2. Implement session restoration, auth observation, sign-in, refresh/recovery, and sign-out.
3. Implement typed profile/chore/comment/attachment records.
4. Implement repositories and relational-select fallback only where live evidence requires it.
5. Build loading/error/session-expired states.
6. Add unit and service-boundary tests.

Exit gate:

- Existing family accounts can sign in on an approved test environment.
- Session persists across relaunch and expired auth returns safely to sign-in.
- Profile and chore fixtures decode.
- Live read checks pass under authenticated RLS without using a service-role key in the app.
- No create/update/delete UI is enabled yet.

### Phase 2 - Home, search, navigation, and personalization (3-4 days)

Work:

1. Implement the native app shell and navigation.
2. Implement Mine/All/Done tabs.
3. Implement cards, due labels, sorting, search, loading, empty, error, retry, and pull-to-refresh states.
4. Refresh safely on foreground return.
5. Implement avatar/initials, profile theme, avatar URL editing, and sign-out.
6. Add Dynamic Type and VoiceOver coverage for these flows.

Exit gate:

- Filter/search/sort fixture tests match PapaBoard.
- Home and Settings UI tests pass.
- A simulator run demonstrates navigation and accessibility-size layouts.
- Live read-only comparison against PapaBoard shows the same visible chores for both users.

### Phase 3 - Chore editing, rich text, and attachments (7-10 days)

Work:

1. Implement new/edit form and validation.
2. Implement assignment, status, date-only/timed due dates, and the legacy sentinel.
3. Implement safe rich-description rendering and editing.
4. Implement multiple PhotosPicker selection and copied-image paste.
5. Implement previews, upload, attachment rows, legacy primary image, removals, and compensation.
6. Implement chore deletion with safe confirmation and partial-failure reporting.
7. Add create/edit/delete tests and attachment failure fixtures.

Exit gate:

- Create/edit/delete succeeds under RLS on an approved test environment.
- Date-only and timed values round-trip without drift.
- Existing rich descriptions render and unrelated edits do not destroy markup.
- Multi-photo upload/remove/gallery ordering matches the web client.
- Injected failures leave no known new Storage or database orphans.
- Physical device verifies PhotosPicker and copied-image handling.

### Phase 4 - Detail, status, comments, Realtime, and calendars (4-6 days)

Work:

1. Implement detail screen and full-screen photo browsing.
2. Implement status cycle and Mark as Done.
3. Implement comment list and submission.
4. Implement scoped Realtime subscription, foreground recovery, and cancellation.
5. Implement Apple Calendar save and Google Calendar handoff.
6. Add deterministic comment and calendar tests.

Exit gate:

- Two clients observe comment changes without duplicates.
- Status changes appear consistently in web and iOS.
- Date-only and timed calendar events have correct duration and reminders.
- Permission denied and calendar save failure states are tested.
- Physical-device EventKit behavior is recorded.

At this point a functional native MVP exists, but native push and release qualification remain incomplete.

### Phase 5 - Native APNs and shared notification delivery (5-7 days)

Work in PapaTodos:

1. Implement permission/status UX.
2. Implement AppDelegate token callbacks and safe token registration.
3. Implement authenticated device register/unregister calls.
4. Implement foreground presentation and notification-tap routing.
5. Add route/auth restoration tests.

Work in PapaBoard backend:

1. Review and commit the `notification_devices` migration.
2. Validate SQL/RLS/RPC behavior in an approved environment.
3. Add APNs secrets without exposing them.
4. Extend `send-push` to deliver Web Push and APNs from one canonical intent.
5. Preserve recipient and delivery-key rules.
6. Add safe provider diagnostics and expired-token cleanup.
7. Deploy only after explicit authorization.

Exit gate:

- Web Push regression checks pass.
- Sandbox APNs accepts a correctly signed request.
- A development device receives assignment, update, comment, and status notifications.
- Foreground presentation is verified.
- Notification tap opens the correct chore after cold launch, warm launch, and session restoration.
- Invalid-token cleanup is evidenced.
- TestFlight/production APNs environment is validated separately before release.

### Phase 6 - Hardening, UAT, and release qualification (4-6 days)

Work:

1. Run the full unit/UI suite and resolve warnings relevant to shipped behavior.
2. Audit accessibility, contrast, dark mode, reduced motion, orientation, network loss, and auth expiry.
3. Verify both family accounts and web/native interoperability.
4. Add required app icons, display name, versioning, entitlements, usage descriptions, privacy metadata, and release configuration.
5. Archive with the intended signing identity.
6. Upload to TestFlight.
7. Execute the UAT checklist on physical devices.
8. Fix release-blocking defects and rerun affected evidence.

Exit gate:

- Release build and archive succeed.
- Automated tests pass with recorded results.
- Required physical-device capability checks pass.
- Backend deployed state and secrets are confirmed without printing values.
- Both users complete UAT for the critical journeys.
- Known non-blocking limitations are documented.
- TestFlight upload is not confused with UAT acceptance or production release.

## 15. Effort summary

| Phase | Estimate |
|---|---:|
| Phase 0 - Foundation and contract audit | 3-4 days |
| Phase 1 - Authentication and services | 3-4 days |
| Phase 2 - Home and personalization | 3-4 days |
| Phase 3 - Editing, rich text, attachments | 7-10 days |
| Phase 4 - Detail, comments, Realtime, calendar | 4-6 days |
| Phase 5 - APNs and shared delivery | 5-7 days |
| Phase 6 - Hardening and release | 4-6 days |
| **Total** | **29-41 engineering days** |

Planning allowance:

- functional MVP through Phase 4: approximately 4-6 weeks;
- full parity through Phase 5: approximately 6-8 weeks;
- production-ready/TestFlight UAT: plan for 7-9 calendar weeks including contingency.

This assumes one experienced iOS/Supabase developer working substantially full-time, prompt access to the two test accounts, Apple Developer/APNs credentials, and a stable existing backend.

## 16. Acceptance matrix

| ID | Requirement | Primary evidence | Phase |
|---|---|---|---:|
| A01 | Existing account signs in and session restores | Auth tests plus approved live check | 1 |
| A02 | Expired auth returns safely to login | Injected expiry test and UI journey | 1 |
| A03 | Mine/All/Done match current rules | Unit fixtures and web/native comparison | 2 |
| A04 | Search fields and due ordering match web | Unit fixtures and UI test | 2 |
| A05 | Theme/avatar settings persist | Repository and UI tests | 2 |
| A06 | Create/edit/delete respects RLS | Approved integration checks | 3 |
| A07 | Date-only/timed chores round-trip | Date and live persistence tests | 3 |
| A08 | Rich descriptions survive display/edit | HTML fixture round-trip tests | 3 |
| A09 | Multiple photos upload/remove without orphaning | Failure-injection plus device checks | 3 |
| A10 | Status cycle matches web | Unit, UI, and interoperability checks | 4 |
| A11 | Comments reconcile through Realtime | Two-client integration check | 4 |
| A12 | Apple/Google calendar behavior is correct | Unit plus physical-device checks | 4 |
| A13 | Native events reach intended recipients only | Backend fixtures and two-account test | 5 |
| A14 | Notification tap opens the correct chore | Cold/warm/device journeys | 5 |
| A15 | Web Push remains operational | Regression test | 5 |
| A16 | Dynamic Type and VoiceOver critical journeys pass | Accessibility audit | 6 |
| A17 | Release archive and TestFlight upload succeed | Xcode/App Store Connect evidence | 6 |
| A18 | Family UAT passes critical journeys | Signed-off checklist | 6 |

## 17. UAT checklist

Run with both family accounts and retain screenshots/log references without exposing credentials.

1. User A signs in and creates a chore assigned to User B.
2. User B sees it under Mine and receives the expected notification.
3. User B opens the notification and lands on the chore.
4. Both users see the same description, due date/time, assignee, and photos as the web client.
5. User B adds a comment; User A sees it through Realtime and receives a notification.
6. User B changes status; both clients show the same value.
7. Date-only and timed chores save correctly to Apple Calendar.
8. Google Calendar handoff contains the correct range and timezone.
9. Multiple photos can be added and one can be removed without losing the remaining files.
10. Search finds title, description, person, and status terms.
11. Done chores move out of Mine/All and appear under Done.
12. Theme and avatar changes are visible after relaunch.
13. Notification disable/sign-out removes or disassociates the native registration as designed.
14. Network interruption produces recoverable errors without duplicate writes.
15. Large text, VoiceOver, dark mode, and permission-denied flows remain usable.

## 18. Decisions required during Phase 0

1. Should the product display name remain **PapaBoard**, become **PapaTodos**, or use another name?
2. Should the first release remain iOS 27.0+, or support an older deployment floor?
3. Should the target remain universal with basic iPad compatibility, or become iPhone-only?
4. Should Swift 6 language mode and complete concurrency checking be enabled immediately?
5. Should notification controls appear on Home, Settings, or both?
6. Is exact rich-text editing parity required, or is safe rendering plus plain-text editing acceptable?
7. Is copied-image paste required in addition to multi-photo selection?
8. Is the intended distribution TestFlight-only initially, standard App Store, or another approved Apple distribution route?
9. Is PapaBoard the permanent owner of shared Supabase migrations and functions?
10. Are Apple Developer membership, bundle-ID capability access, and APNs signing credentials ready?

Recommended planning defaults are:

- retain iOS 27.0 for the first build because it matches the current project;
- remain iPhone-first while keeping the universal target buildable;
- use Swift 6 strict concurrency if supported cleanly by the installed toolchain and selected Supabase SDK;
- display notification management in Settings with a contextual Home prompt while permission is not determined;
- preserve exact rich-description content;
- keep shared backend ownership in PapaBoard;
- use TestFlight for initial family UAT before any production-release decision.

## 19. Working procedure for every phase

1. Re-read this specification and applicable guidance.
2. Inspect both working trees and preserve unrelated changes.
3. Confirm the requested phase and its exit gate.
4. Implement only that phase.
5. Run the phase's build, tests, and static checks.
6. Perform simulator and physical-device checks only where applicable.
7. Record backend deployment separately from local code.
8. Update `docs/phase-N-validation.md` with actual evidence.
9. Stop at the phase boundary for review before starting the next phase.

## 20. Source and verification notes

This specification is based on direct inspection of:

- the current PapaTodos starter Xcode project;
- the current PapaBoard React/Supabase implementation;
- the existing PapaBoard SQL migrations and Web Push Edge Function;
- the draft iOS notification-device migration;
- the official Supabase Swift package documentation for package installation, client composition, and Realtime support.

Primary SDK references:

- Supabase Swift: <https://github.com/supabase/supabase-swift>
- Apple UserNotifications: <https://developer.apple.com/documentation/usernotifications>
- Apple PhotosUI: <https://developer.apple.com/documentation/photosui>
- Apple EventKit: <https://developer.apple.com/documentation/eventkit>

No source implementation, Xcode build, simulator run, Supabase mutation, migration deployment, Edge Function deployment, APNs request, TestFlight upload, or physical-device validation was performed while writing this planning document.
