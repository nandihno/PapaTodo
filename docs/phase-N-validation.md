# Phase N validation — <phase name>

> Template. Copy to `phase-<N>-validation.md` for the phase actually being recorded and fill in every section with real evidence. Do not mark an item done without a command, log excerpt, or screenshot to back it up. See specification.md sections 13.5 and 19.

Date:
Phase scope (link to specification.md section):

## Files and behavior changed

-

## Build

Command run:

```bash
```

Result:

## Test compilation

Command run:

```bash
```

Result:

## Tests actually executed

Command run:

```bash
```

Result (pass/fail counts, not just "succeeded"):

## Simulator journeys executed

-

## Physical-device checks executed

-

## Backend changes reviewed/deployed

- Reviewed in PapaBoard repo:
- Deployed (state, not just written):

## Known limitations and follow-up work

-

## Deployment-boundary checklist (specification.md section 3.3)

Mark only states actually reached, not implied by an earlier state:

- [ ] specification written
- [ ] native code implemented locally
- [ ] native build succeeded
- [ ] test bundles compiled
- [ ] simulator tests executed
- [ ] Supabase migration reviewed
- [ ] Supabase migration deployed
- [ ] Edge Function deployed
- [ ] APNs accepted a request
- [ ] a physical device received and opened the notification
- [ ] TestFlight build uploaded
- [ ] family UAT passed
- [ ] production release approved
