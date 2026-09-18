# PapaBoard parity checklist

Per specification.md section 14 (Phase 0, item 12): "Freeze a feature-parity checklist against an exact PapaBoard source snapshot."

**Important caveat on "exact snapshot":** the behavior described below — specifically the Home tab set (including Done) and the overdue-first sort tie-break — only exists in PapaBoard's **uncommitted working tree** as of 2026-09-19, on top of commit `4d4217652087667b4cb800eb1721631d0a0d4f49` ("Enable Realtime for chore_comments"). The last *committed* version of `src/screens/HomeScreen.jsx` has a simpler sort (no overdue-recency reversal) and no Done tab. specification.md's own description of "current" behavior (section 9.2's sort order, in particular "overdue, with the most recently overdue first") only matches the uncommitted code, not the last commit. If that working-tree change is lost or reverted before being committed, this parity baseline is stale — check `git diff src/screens/HomeScreen.jsx` in the PapaBoard repo before trusting this document again.

## Ported to Swift (verified against source, with passing tests)

| Behavior | PapaBoard source | Swift port | Tests |
|---|---|---|---|
| Date-only sentinel detection (`hasDueTime`) | `src/lib/dueDates.js:29-40` | `DueDateRule.hasDueTime`/`isDateOnly` | `DueDateRuleTests.swift` |
| Due-state tone (done/overdue/today/upcoming) | `src/lib/dueDates.js:61-104` (`getDueDisplay`) | `ChoreDueState.tone` | `ChoreDueStateTests.swift` |
| Sort rank + key (due today, overdue-most-recent-first, future, no date) | `src/screens/HomeScreen.jsx:347-370` (`getDueSortRank`/`getDueSortTime`, **uncommitted**) | `ChoreDueState.sortRank`/`sortKey`, `ChoreSort` | `ChoreSortTests.swift`, `ChoreDueStateTests.swift` |
| Newest-creation tie-break | `src/screens/HomeScreen.jsx:329-345` (`compareChores`) | `ChoreSort.areInOrder` | `ChoreSortTests.swift` |
| Mine/All/Done tab membership | `src/screens/HomeScreen.jsx:278-292` (`choreBelongsInTab`, **uncommitted**) | `ChoreFilter.belongs` | `ChoreFilterTests.swift` |
| Search across title/description/assignee/creator/status | `src/screens/HomeScreen.jsx:306-327` (`choreMatchesSearch`, `getStatusLabel`) | `ChoreSearch.matches`/`statusLabel` | `ChoreSearchTests.swift` |

## Deliberately simplified during the port (behaviorally identical, verified against source)

- `getDueDisplay`'s "Tomorrow" case and the `dueDay < afterTomorrow ? 'today' : 'upcoming'` branch in the final `else` are dead code in the JS — by the time either is reached, `dueDay` is always ≥ `afterTomorrow`, so the ternary is always `false`. `ChoreDueState.tone` collapses these into a single `.upcoming` result for every non-today, non-overdue, non-done chore. Same for `getDueSortRank`'s unreachable trailing `return 3`.

## Not yet ported (out of scope for Phase 0, needed by later phases)

- **HTML-to-plain-text conversion for search** (`src/lib/descriptionHtml.js:57-70`, `descriptionToPlainText`) — uses browser DOM APIs to sanitize and strip HTML tags. `ChoreSearch.matches` currently searches `description` as-is; this is correct for plain-text descriptions and only degrades (searches raw markup) for HTML ones. Needs a real HTML parser — Phase 3 scope (rich-text rendering/editing).
- **`mergeCurrentUserProfile`** (`src/screens/HomeScreen.jsx:264-276`) — overlays the current user's freshly-edited profile (name/avatar) onto a chore's joined `assignedProfile`/`createdProfile` snapshot before display/search, so a just-changed name/avatar shows immediately without waiting for a full chore refetch. Requires live profile state; Phase 2 concern.
- **Due-date display label strings** (e.g. "Overdue at 3:00 pm", "Tomorrow", weekday/month formatting) — `formatDetailDueDate`/`getDueDisplay`'s label construction in `src/lib/dueDates.js`. The Swift port only implements the semantic *tone* (done/overdue/today/upcoming) and sort key, not the display string, since exact locale/format matching is a presentation-layer concern better finalized alongside the actual card/detail views in Phase 2.
- **Calendar event construction** (`getDueCalendarParts`, `formatCalendarDate(Time)` in `src/lib/dueDates.js:106-147`) — Phase 4 scope (EventKit integration).
- Relational-select-with-fallback pattern for chores/profiles (`src/lib/chores.js`) — informs Phase 1's repository implementation but wasn't ported since Phase 0 has no live Supabase-backed repository yet (only fixtures).
- Attachment handling, comment authoring/Realtime UI wiring, notification recipient logic, rich-text sanitization — not yet read in PapaBoard source; each is scoped to its own later phase (3, 4, 4, 5, 3 respectively).

## How this was produced

Read directly from the PapaBoard working tree on 2026-09-19: `src/lib/dueDates.js`, `src/lib/chores.js`, `src/screens/HomeScreen.jsx`, `src/lib/descriptionHtml.js` (partial), `src/screens/ChoreDetailScreen.jsx` (Realtime subscription only, see `project_supabase_audit_2026-09-18` memory / the `enable_chore_comments_realtime` migration). Ported logic lives in `PapaTodos/Domain/Rules/` and is covered by `PapaTodosTests/{DueDateRule,ChoreDueState,ChoreSort,ChoreFilter,ChoreSearch}Tests.swift`.
