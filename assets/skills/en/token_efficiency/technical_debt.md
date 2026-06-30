---
name: technical-debt
description: >
  Harvest every `senior:` comment in the codebase into a debt ledger, so the
  deliberate shortcuts and deferrals senior mode leaves behind get tracked.
  Trigger with "technical debt", "/technical-debt", or "what did we mark to do later".
license: MIT
---

# Technical Debt Ledger (Simplification Comments)

Every deliberate shortcut is marked with a `senior:` comment naming its ceiling and upgrade path. This collects them into one ledger so a deferral can't quietly become permanent.

## Scan

Grep the repo for comment markers, skipping `node_modules`, `.git`, and build output:

`grep -rnE '(#|//) ?senior:' .`

Each hit is one ledger row.

## Output

One row per marker, grouped by file:

`<file>:<line> — <what was simplified>. ceiling: <the limit named>. upgrade: <the trigger to revisit>.`

The convention is `senior: <ceiling>, <upgrade path>`.

## Risk Flags

Any `senior:` comment that names no upgrade path or trigger gets a `no-trigger` tag.

End with `<N> markers, <M> with no trigger.` Nothing found: `No technical debt. Clean ledger.`

## Boundaries

Reads and reports only, changes nothing. To persist it, ask and it writes the ledger to a file (e.g. `DEUDA-TECNICA.md`). One-shot.
"stop senior mode" or "normal mode" to revert.
