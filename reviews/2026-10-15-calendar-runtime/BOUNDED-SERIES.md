# Calendar series through the existing bounded owners

This child of the Calendar lowering/registry unit realizes its originally
checked series with the admitted immutable table and existing Calendar cursor.
It does not duplicate civil conversion, inverse lookup, timezone selection,
gap/fold handling or UTC boundary ordering. It retains one cursor and one pending
interval, followed by the existing admitted-output and trusted-completion owners.

The original bounded Session owns continuation tokens, cancellation observation
and terminal state. Cursor work is charged cumulatively and each advance remains
within its quantum; interval emission and finalization each charge one control
step. Output value admission retains its own original finite value budget. There
is no per-row/yield reset, unbounded boundary array or fixed-millisecond grid.

Two existing execution-relation functions are exposed to trusted internal
Runtime consumers without changing their bodies: bounded admitted-output
preparation and bounded output reclamation. A confirmed no overlapping edit in
these functions. The Calendar caller retains the original output handle when
reclamation returns false, and retries that same Owner. Accepted completion
never clears retained rows; cancellation clears private containers in the
Owner's existing bounded slices. No cleanup ACK is inferred from stopping.

The initial three controls reached the new start API but failed (0/3 at
`17330a65`, `run-3H27KP`). The shared physical Schema orders fields canonically,
so its slots are `end`, then `start`. The caller now resolves the original field
contracts by name and supplies values in that original Schema's slots; it does
not impose an authored SELECT/Named Result order on physical storage. Original
full interval values remain unchanged. Named Result order still belongs to the
existing publication projection. The schema correction passes the original
three controls at `53234873` (`run-MNKAIc`).

Four actual component controls at `4caeacf0` (`run-A9Vane`) cover:

- Full unclipped intervals across the year boundary, exact physical field names
  and values, quantum 1/7/64 with equal cumulative logical control work, accepted
  output after cleanup, and no advance after terminal.
- Typed empty completion at the exact one-step finalization limit, zero-work
  refusal and wrong-coordinate refusal.
- Cancellation after at least 130 private output rows, false/pending cleanup
  followed by bounded reclamation of the same handle, and no stopped advance.
- The original value-weight law: 59 work per two-timestamp row, exact two-row
  118 accepted and one-short 117 rejected with `CalendarOutput(CaptureLimit)`.
  This is value accounting, not a measured replacement for a capacity bound.

The ordinary Runtime registry generator supplies filesystem-free test contract
bodies from its existing SSOT. API generation/consuming type checks use normal
`moon info` for execution-relation, local-TEA and its provider on JS/Wasm/Native.
These do not execute Native/Wasm or prove installed execution.

The managed provider wrapper preserves the original selected step coordinate,
same generated sequence and control, cumulative progress/work deltas, terminal
observation and cleanup retry. Its default installation/source-free classification
and the bucket continuation remain the next connection. No ambient TZDB,
default profile, new executor, scheduler, resource Owner or publication authority
is installed. Calendar Local/HTTPS E2E is still zero; the original six declared
public controls and remaining Frontend goal stay unfinished.

The next integration counter separated the conservative preparation bound
(four for a declared two-day range) from the actual output quota. At `6da23a15`
the unchanged kernel wrongly rejected quota two before execution (4/5,
`run-7lQOrK`). Removing only that start-time comparison retains the original
static bound for preparation/capacity and lets the original cursor and output
Owner enforce actual rows. Quota two must emit exactly the two independently
expected intervals; quota one must fail with `CalendarBoundary(SeriesRowLimit)`
and keep cleanup custody. Neither the numeric limits nor expected rows change.

```sh
node reviews/2026-10-15-calendar-runtime/prepared-calendar-kernel.mjs <SHA> kernel
node reviews/2026-10-15-calendar-runtime/prepared-calendar-kernel.mjs <SHA> api
node reviews/2026-10-15-calendar-runtime/prepared-calendar-kernel.mjs <SHA> generator
```

The test recipe selects one file with nonzero discovery, JS j1,
nonHeavy270/TERM5 and child240. No full Core, Proof, new producer/consumer,
Provider I/O, Hosted CI or formal publication is part of this finite unit.
