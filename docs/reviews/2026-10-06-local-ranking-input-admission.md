# Retained ranking: resumable input admission

Parent: `a2dfdf3b88d1b412af196ad0bde8a22cd8673c3f` (#537, output admission).
The parent remains unmerged; this unit retains its dependent base.

## Production boundary

Ranking previously called the completed/supplied input's checked-cell helper
inside one charged field-read transition. That helper rechecked the whole
value, including columns unused by the ranking policy. A large admitted Array
could therefore hide its complete traversal inside a single ranking step.

The existing ranking Session now owns a `RecheckField` phase and one common
value-admission cursor. Completed Text is staged raw without a synchronous
Text constructor; supplied values and other completed cells use the same
contract recheck. Only cursor completion binds the checked value to its
group/candidate/tie/score/rank role. Unused columns remain validated.

The common cursor additionally advances Vector components individually and
JSON data Text in 64-UTF-16-unit chunks. Vector node/depth accounting and
rejection of NaN, infinity and negative zero are unchanged. JSON preserves
Unicode composition and CR/LF; no settings normalization is applied.
Array/Object child traversal reuses the existing continuation stack.

The ranking owner reserves eight additional fixed slots and `max_depth+2`
continuation slots before reading input. Arithmetic is overflow checked.
Stop is checked between polls; cleanup before confirmed stop still returns
`NotStopped`. Stopped cleanup cancels the cursor once without closing either
caller-owned input. Work remains cumulative across quanta.

No algorithm, NULL semantics, score policy, provider binding, result order,
CID, retention format, Run controller, scheduler or ledger is replaced.
The generated ranking API adds a read-only input-poll observation, not a
new completion or publication authority.

## Independent boundaries

The numeric RRF fixture adds two recheck polls for each of three scalar
fields in four records: 24. Existing 212 control work becomes **236/235**.
Its structural workspace is now **137/136**: previous 117 + eight fixed
slots + twelve depth-ten continuation slots.

Each long-key record adds six scalar polls and two eleven-poll Text rechecks:
`6+2*11=28`, or 112 across four records. The previous 14081 control boundary
becomes **14193/14192**; workspace becomes **156/155**. Comparison work and
the two output rows' independent logical limits remain unchanged.

The unused-array fixture has one record and an empty opposite input:

- Input: one group initialization, four field reads, six scalar recheck
  polls, `2*257+3=517` array polls and four validation/store polls = 532.
- Remaining scratch, duplicate/rank, fusion and output phases = 42.
- Total control **574/573**; workspace **78/77**. Input node allowance
  **258/257** independently distinguishes the whole admitted Array limit.
- Quanta 1, 7 and 256 agree on one literal expected row with score 0.5.
  A barrier at input poll 64 retains both inputs and the pending cursor
  before physical stop; stopped cleanup clears cursor/scratch/output scope
  once. Neither failed work nor node admission produces CompletedOutput.

An atomic-drain mutation made the owning fixture fail at **55 versus 574**
(`run-STu6PR`), so whole-value rechecking cannot masquerade as bounded input
work. The mutation was restored before final caller/Host verification.

Shared Vector and nested JSON fixtures compare node/text usage with the
existing synchronous admission contract, then independently assert literal
counts, one-short limits, component positions and stopped cursor cleanup.

## Ordinary Program and retained Store

The existing public RRF Program has two source-free Values producers, one
ranking stage and two separate consumers. All three named outputs are read
explicitly and compared with authored ordered rows. Same-request reuse adds
no dispatch or advances.

The added variant supplies `zz_unused` arrays. Its initial 257-item/two-row
literals failed preparation with the existing typed
`ValuesRecursiveIssue.BytesExceeded`: their 1030 canonical bytes exceed the
unchanged 1000-byte nested Values policy. The public fixture therefore uses
129 items per row, independently totaling 518 bytes. This is not a policy
increase or an alternative runtime; the 257-item kernel boundary stays intact.

For this variant the first ranking quantum pays 23 initialization/scalar/Text
polls and one array-read step. The remaining 232 of 256 polls cannot complete
the array's 261-poll recheck. The existing awaited Host observation then
delivers cancellation inside the pending input, not at a pre-start barrier.
The request is persisted while stop remains unconfirmed; inputs/snapshots
remain, no Named Result is exposed, and confirmed stop reclaims snapshots.
Dispatch/completion counts do not increase during reuse or cleanup.

## Executed evidence

- Shared recheck plus ranking workspace/key components JS candidate:
  14/14 (`run-BhFQPp`). Earlier ranking callers passed 15/15 (`run-ieaKqV`).
- Final ranking caller source: 15/15 (`run-aExQkR`,
  `focused-test-nXvqCY`), including producer, supplied/scored and standard
  Host callers selected by `*ranking*`.
- Fresh `local-node` and `run-host-core` runtimes were prepared with the
  pinned toolchain from this source; compiled payloads remain ignored.
- Final ordinary retained Host: 2/2 (`run-BxiRq1`,
  `focused-test-SkFCuP`), long comparison and unused-array cancellation.
  The initial public failure is retained as `run-lbbKeK`; the narrow typed
  diagnostic is `run-XuLLGD`. Its temporary logging overlay was removed
  before the successful run and is not part of this change.
- Final selected resource-role/suite mutations and operation inventory:
  11/11 (`run-0pdaM4`, `focused-test-Qx6O4I`). The real resource checker
  also passed. Its earlier failure exposed an absent `moon:value_admission`
  suite-directory registration; the explicit mapping now requires the
  existing three-target suite and matching source directory. A mismatched
  suite/path mutation rejects, as do removed input/shared/public evidence.
  Full boundary completion is not asserted by this checker run.
  The submitted full SHA is recorded in the PR.

Commands select the owning JS caller file and public Host file through
`scripts/local-checks.mjs`; no all-Core or all-target campaign is implied.
The candidate sources emitted the parent's existing unused index-sort and
typed encoding-field warnings. Deny-warning compilation is not claimed.

## Residual work

This closes nested input child/vector/Text admission on the tested paths,
not every potentially long operation. Object field-name validation/matching,
ranking authored-name binding and some other VecA input readers remain
synchronous and need their own source-bound assessment. The existing
`max_noninterruptible_value_*` readers remain conservative policy ceilings,
not measured maximum resume latency.

Whole-Run exact Ledger limits, packed/HTTP, Wasm/native, fresh-process replay,
wall-clock cancellation latency and new Store-failure campaigns were not
executed for this unit. Existing retained cleanup owners are reused; this
record does not replace their independent fault evidence or close all Local
Compute retention.
