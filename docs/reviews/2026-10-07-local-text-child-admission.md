# Retained raw Text child admission

Base main: `be30c8fdf2b3133219f7becc74c5667619806c70`.
Initial parent: #686 (`647b03801232fe7b9e87e4f1a32a36e5069086f5`).
Branch: feat/local-text-child-admission. Parent adoption determines the PR base;
the final target is main. This closes shared Text conversion, not all retention.

## Counterexample and existing owners

The Object continuation called admitted_aggregate_item on a raw Text child.
That synchronously computed its full UTF-8 length before charging control and
called text_value for a second complete validation. The independent 256-unit
bounded-poll regression failed 0/1 (`run-87qFC8`, `focused-test-rcP3hg`).
The array_agg finisher had the same scans around its one-unit charge loop and
copied the complete admitted array at completion. Its previous cancellation
callback only set a closed flag; it could not dispose a newly pending cursor.

Both production consumers now share RawTextAdmission, a private continuation
of the existing Value start_recheck_runtime_text/advance/cancel owner. Its
unconstrained scalar String contract reproduces the former text_value Unicode
and UTF-8 validation ceiling; it does not replace enclosing typed admission,
expression roots or authority. Only a complete recheck yields an admitted
value. Then the original UTF-8 byte control charge is paid one unit per poll.
There is no second validation, normalization, logical work charge or root
issuance. Three reserved handles cover state, recheck owner and scalar frame.
Short Text (at most 64 units) keeps its existing fixed scan.

ObjectText remains in the same expression frame while its child and growing
Object roots stay live. The previously paid continuation transition is not
charged again. The existing append receives the completed admitted value;
failure or cancellation closes the recheck and the same frame/builder roots.

AggregateArray uses the existing ArrayBuilder, appending one admitted item at a
time and transferring its finished backing, not copying it. Item reservations
remain with the output's enclosing row scope; the temporary builder reservation
is released on success. Failure/stop cancels builder and recheck, returning
only this finisher's reservations. AggregateDirect now calls that cleanup owner,
not a flag-only cancellation. No Compute, I/O or finished item is replayed.

## Independent limits and semantics

- A 256-byte Text child has weight 257 and wire 258. Object {p:Text} has
  weight 259 and wire 264. Two entries plus child produce/consume plus Object
  result give `2 + 257 + 257 + 259 = 775` work. Exact 775/774 is checked.
- Object and child coexist at peak `264 + 258 = 522`, so live 522/521 is
  independently fixed. The existing Text measurement's ten handles plus three
  Object handles require workspace 13/12. The conversion's three handles plus
  reserved field/child fit below that peak. Batching 1/7/256 is equivalent.
- The unscoped Object has fifteen transition/reference/name units plus the
  original 256-byte Text charge: 271 control. No poll charges the full value.
- One array contributor requires `1 + 256 = 257` control; 256 fails RowLimit.
  Item/builder two handles plus three conversion handles require 5/4 workspace.
  Successful transfer leaves one item reservation for the enclosing row scope;
  double close cannot reclaim it. Failed/stopped finishers leave zero.
- A pre-existing caller Number root accounts for one work/byte. Object stop
  during validation or charge retains work 517 and live 523 until cleanup,
  then leaves only that caller root. It is explicitly released separately.
- At the surrogate boundary, 63 ASCII + supplementary four bytes + NFD three
  bytes + CR/LF two bytes require 72/71 control. Completed Text preserves the
  exact scalar sequence; malformed isolated surrogates are rejected. Array and
  Object cancellation is exercised in both validation and charging phases.

## Ordinary public retained Programs

The existing installed Local Host name harness also receives Values with a
1024-unit prefix plus supplementary, NFD and CR/LF data. A later producer
constructs {p:payload} or groups by id with ordered array_agg(payload), then
two consumer Stages project id/value. Each explicit Named Result is read from
the real Store and compared to independent ordered rows and nullable/closed
column contracts. The NULL Object child remains NULL; the all-NULL array group
produces an empty nonnullable array. No NFC/LF data replacement is accepted.

The ordered-array Program explicitly asserts its input id key before export;
that is authored Program evidence, not injected internal state. Earlier
unkeyed preparation was refused, and an experimental assertion reused an
existing alias and was also refused. The corrected ordinary Program uses a
distinct keyed alias. A diagnostic pure checker probe was never dispatched and
was removed; the final acceptance uses only public submission/Result access.
Public JSON check is unsupported by the current check endpoint and is not used
as a substitute for submission. No order/key checking was weakened.

Both cases reuse the public post-progress cancellation barrier, preserving
snapshots until confirmed stop, refusing all three Results, and reclaiming
snapshots without additional dispatch. The barrier is opaque: exact conversion
phase stops are established by common fixtures, not claimed from the Host hook.
Existing Store failure/retry evidence remains separate; a new full fault matrix
or Native/packed acceptance is not inferred here.

## Evidence consistency and checks

Required derive and group roles bind the new exact/stop/public cases; removing
them fails the resource checker. The actual inventory still reports 64 mapped
routes/four typed refusals and does not assert full Local completion.

A separate inherited baseline failure was fixed in commit 788f36db1: the pure
operation table pointed current Graph construction to a public refusal suite
and called Graph retired. It now points to existing executed keyed construction;
the refusal test and classification remain strict. That referenced constructor
test was independently executed 1/1 (`run-ev6VFM`, `focused-test-MYItFa`). No
Graph kernel or protocol changes are part of the correction.

Candidate shared/caller JS passed 51/51 (`run-rtHKvc`, `focused-test-BhEO0l`).
Candidate public/resource/inventory Node passed 10/10 (`run-bx94me`,
`focused-test-aLIUXk`). Local Node and Run Host Core were built from changed
source only (`run-bLNq0g`); ignored runtime assets/wrappers match. API generation
has no tracked changes; Node Host/Workers freshness checks pass. Final submitted
SHA, commands/receipts and automatic CI are recorded in the PR separately.

Not run: full Core, Wasm/native, Native heap-layout certification, proof campaign,
packed/HTTPS or performance. Source Host success is not distribution acceptance.
#677's independent Native runtime-capacity review remains outstanding.

## Remaining boundaries

Initial row-name/Map preparation and worst-case short-name Map collisions are
separate. AggregateString still computes long UTF-8 lengths and joins its final
strings synchronously; this unit does not relabel memory limits as bounded
execution there. Broader retained shapes and the four current Graph refusals
remain governed by the live production inventory, not historical completion
claims. No independent scheduler, ledger or storage implementation is added.
