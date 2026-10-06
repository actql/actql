# Retained string aggregation cursor

Initial parent: #692 at `6c460087c2fb77833cd0abe07e86e202fbf0ecc6`.
Branch: feat/local-string-aggregate-cursor; final target: main. Parent adoption
is checked before publication, not assumed. This is not all Local completion.

## Counterexample and shared production connection

The existing AggregateString finisher synchronously sized each contributor;
AggregateDirect synchronously sized a demanded delimiter before starting it.
The final strings.join copied the full output in one completion call. The valid
256-unit sizing regression failed 0/1 (`run-3iUR1y`, `focused-test-RzJS0U`).

The same finisher now has delimiter sizing, item sizing, original byte charging,
buffer admission and scalar construction phases. It uses the existing
text_function_scalar and pinned StringBuilder, not another evaluator, storage
engine or ledger. The parent's pre-start delimiter scan and flag-only close
are removed. A cursor owns cleanup until success or confirmed disposal.

Complete item sizing still precedes its original total-byte/remaining-separator
checks and charge. The byte and unit totals and pending charge are Int64;
no large admitted byte balance is narrowed into a negative Int pending count.
Zero/singleton contributors do not inspect an unused delimiter. Data keeps its
raw scalar sequence, NFD and CR/LF. NULL contributor filtering and empty-group
NULL remain in the unchanged AggregateDirect owner.

All output bytes and UTF-16 units are admitted before builder allocation.
Two state/builder handles and the exact buffer capacity are reserved. Native's
byte-sized Int hint is checked before multiplication/allocation; capacity failure
is a resource refusal, not a String type restriction. Each build poll appends
one scalar without a second control charge. The pinned Native exact-capacity
to_string transfers backing; JS returns its retained String. No final join or
explicit output copy is used. VM allocation/rope costs are not claimed constant
time or certified as Native stop latency by these tests.

On success, buffer reservations pass to the enclosing row scope; only temporary
handles are released. An empty builder's minimum backing is discarded rather
than transferred. Failed/stopped states drop the builder and release their own
reservations once, retaining borrowed input values and spent control work.

## Independent boundaries

- First input: 63 ASCII, supplementary scalar, NFD e/mark, CR/LF = 72 bytes
  and 69 units. Delimiter: 65 ASCII + CR/LF = 67 bytes/units. Last input end =
  three bytes/units. Total bytes/control = 142; buffer = 139 units, workspace
  peak = 139 + two handles = 141. Exact/one-short 142/141 control, 142/141
  byte ceiling, and 141/140 workspace are checked with typed RowLimit.
- A one-short byte ceiling refuses before charging the second contributor:
  total remains 72 and control remains 70. Work/workspace one-short cases
  preserve their independently expected consumed charge, not arbitrary failure.
- Batching 1/7/256 preserves output and total charge; each charged poll consumes
  at most one control unit. No algorithm sizing poll scans the whole Text.
- Cancellation at offset 64 in delimiter/item sizing, pending charge 128, and
  built units 64 reclaims state/buffer without releasing borrowed inputs,
  refunding work, or continuing a closed finisher. Double close is harmless.
- Empty/singleton demand, empty Text, malformed demanded surrogate, and an
  undemanded malformed delimiter are fixed independently.

## Actual public retained Program

The existing public Host harness now submits Values with an asserted input id
key and bucket, then string_agg -> rename -> select in one producer Stage and
two consumer Stages. A two-member bucket combines long raw Unicode input,
256-unit delimiter and end; the all-NULL bucket yields NULL. All three explicit
Named Results read the independent ordered rows and nullable String schema
from the real retained Store. Same-request reuse performs no new dispatch.

Delivered post-progress cancellation retains snapshots while physical stop is
unconfirmed, publishes none of the three Results, and reclaims them without
additional dispatch. This public hook is opaque; four exact finisher phase
stops are proved separately by common fixtures. Existing Store failure/retry
evidence is not relabelled as a new full mixed-path fault campaign.

Required group limits/stop/public roles fail if removed. Existing Refusal and
execution inventory checks remain strict. Candidate JS/caller batch passed
27/27 (`run-PhOXrM`, `focused-test-pRIE8q`); public/resource/inventory Node
passed 11/11 (`run-uSqRw9`, `focused-test-VdrPUq`). Only consuming Local Node
and Run Host Core runtimes were rebuilt (`run-cPyK0f`), with ignored bundles
and tracked wrappers checked. Final SHA commands/receipts are in the PR.

No public API, schema, wire, CID, pins or language changes. Full Core,
Wasm/native, physical heap/stop certification, proof campaign, packed/HTTPS
and performance were not run. Checkout Host success is not distribution or
CI success. #677's Native runtime-capacity review remains independent.

Remaining synchronous initial row-name/Map preparation and short-name collision
behavior are separate. Broader retained shapes and current Graph refusals still
require their own authoritative production/variant evidence.
