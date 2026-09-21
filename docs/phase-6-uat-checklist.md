# Papa Todos — family UAT checklist (specification.md section 17)

Run on the TestFlight build with both accounts (User A and User B), on physical iPhones. Tick a line only when you have seen it happen; write anything odd next to it. Do not put passwords or screenshots of credentials in this file.

TestFlight and UAT are separate things: installing the build proves it archives, signs and runs. This checklist is what says it is good enough to rely on.

Build under test: 1.001 (2) &nbsp;·&nbsp; Date run: ____ &nbsp;·&nbsp; User A: ____ &nbsp;·&nbsp; User B: ____

| # | Journey | Seen working | Notes |
|---|---|---|---|
| 1 | User A signs in and creates a chore assigned to User B | [ ] | |
| 2 | User B sees it under Mine and receives the notification | [ ] | |
| 3 | User B taps the notification and lands on that chore (try with the app closed) | [ ] | |
| 4 | Both see the same description, due date/time, assignee and photos as the web app | [ ] | |
| 5 | User B adds a comment; User A sees it appear live and gets a notification | [ ] | |
| 6 | User B changes the status; both clients show the same value | [ ] | |
| 7 | A date-only chore and a timed chore both save correctly to Apple Calendar | [ ] | |
| 8 | Google Calendar handoff has the right date range and time zone | [ ] | |
| 9 | Add several photos, remove one: the rest are still there | [ ] | |
| 10 | Search finds a title, description word, person and status | [ ] | |
| 11 | A Done chore leaves Mine and All and appears under Done | [ ] | |
| 12 | Theme and avatar changes are still there after quitting and reopening | [ ] | |
| 13 | Turn notifications off, or sign out: that phone stops receiving pushes | [ ] | |
| 14 | Turn on airplane mode mid-save: a clear error, and no duplicate chore after reconnecting | [ ] | |
| 15 | Largest text size, VoiceOver, dark mode, and denying notification permission all stay usable | [ ] | |

## Sign-off

- User A: ____ &nbsp; Date: ____
- User B: ____ &nbsp; Date: ____

Anything that fails goes here with what you did and what you saw:

