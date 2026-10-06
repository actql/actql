# Bounded Events record emission

## Completion unit and dependency

This component starts at #585,
`feb175d059b17b0176106564f05f9157009a4db2`. That parent is now adopted;
the base and final merge destination are main. It closes record emission in
watermark, fixed/sliding window, dedupe and Events/Relation session. It
does not claim completion of every retained Local execution boundary.

Each kernel previously appended a complete record synchronously. Window
also copied its complete input field array in one transition. Yielding
between records did not interrupt a large unused value inside that work.

The existing bounded Session now retains the common RecordAppend cursor.
Every append poll consumes one control step, including nested value and
Text wire fragments. Window copies one input field per poll. Output
progress is reported only after the cursor commits; CID, record order,
window membership and session identity rules are unchanged. No second
evaluator, scheduler, ledger or record algorithm is introduced.

## Reservation and custody

The shared append API accepts an optional caller-scratch reservation,
defaulting to zero. The cursor carries it while dynamic contract scanning,
identity collision comparison and the next retained row coexist. It does
not become retained output capacity after commit. Negative/overflowing
reservations and insufficient capacity are rejected before allocation.

Watermark reserves its field references and row handle. Window reserves
both source and emission arrays and their handles. Dedupe and session
include their existing full persistent scratch, emission references and
row handle. The pre-emission check includes the next retained row; deeper
contract/collision continuations still use the common append checks.

A cancellation request alone releases neither input nor provisional
output. Session stop precedes cursor cleanup and builder cancellation.
Cleanup clears the cursor and kernel scratch once; completed output is
still transferred through the existing completion owner.

## Independent boundaries

The common fixture has one numeric identity, a numeric clock and an unused
513-unit Text. Primitive Events append takes `6*width+2*identities+8`
polls; Relation append takes `6*width+6`. Long Text adds nine polls.
Cursor space is `16+3*width+identities+3*depth`, plus caller scratch and
the next retained row's `width+2` slots. At depth ten:

| Kernel | Control exact / one-short | Workspace exact / one-short |
| --- | --- | --- |
| Watermark | 62 / 61 | 80 / 79 |
| Fixed window | 62 / 61 | 79 / 78 |
| Dedupe | 68 / 67 | 70 / 69 |
| Events session | 99 / 98 | 90 / 89 |

Quanta 1, 7 and 256 preserve these boundaries and logical construction
work 28, 24, 16 and 28 respectively. Typed control/workspace failures,
contents, once-only cleanup and input survival are asserted. A separate
fixture requests cancellation after 32 append polls, inside the Text
walk; stop retains charged work and cleanup reclaims provisional output.

The shared scratch fixture independently checks 39/38 slots, unchanged
logical work six, negative reservation rejection, and collision comparison
55/54 slots while a prior row remains owned until cancellation. Existing
fixed/sliding, timestamp, late-drop, dedupe, Events and Relation session
boundaries are updated from their actual phase schedules, not from a
successful run's reported total. The arithmetic termination fixture's
finite poll cap now includes the newly split emission phases.

## Ordinary Host evidence

Four ordinary JSON Programs use Values -> to_events -> the operator ->
events, followed by two separate select consumers. A real installed Store
holds the output. Named Results must contain exactly published,
consumed_a and consumed_b; every row is compared without unordered sorting
to independently specified contents. Session identity is the existing
length-prefixed spelling `session:12:v:1:1:v:1:1`.

The unused values are an 8,193-unit Text and a 129-item numeric Array.
Their combined wire walk crosses the Host's 256-poll quantum while staying
within the installed 10,000-byte record and ten-Result-field ceilings.
After the four-field bridge reports work five/progress one, an awaited
test barrier stops the operator at work 256/progress zero, inside record
value emission. No sleep determines that boundary. Requesting cancellation
does not change the Store files or advances before physical stop. The
terminal Run is cancelled, all three Results are unavailable, no further
positive Compute observation or dispatch occurs, and snapshot custody is
reclaimed. A stop-confirmation poll is not counted as Compute progress. Successful
request reuse returns the same Run and rows without new Compute.

Early candidate fixtures exceeded the installed record or Result field
ceilings. Those failures are retained as diagnostics, not reported as
Events bugs or successful acceptance; no product ceiling was increased.

## Executed candidate checks

The affected TEA, registered consumer and shared record JS selection passed
80/80 (`run-rrkEMX`, `focused-test-Weh2LL`). The final public Store/cancel
cases and gate mutations passed 7/7 (`run-8ERDYX`,
`focused-test-34rzOs`). Removing required operation roles or Host import,
borrowing a foreign suite, or removing the common append connection makes
the accounting gate reject the affected operation. Route inventory counts
are unchanged: this records stronger boundaries, not new operation support.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/local_tea src/query_integration/local_carrier_events_wbtest.mbt \
  src/managed_record_storage/append_steps_wbtest.mbt \
  src/managed_record_storage/contract_steps_wbtest.mbt \
  src/managed_record_storage/identity_steps_wbtest.mbt \
  src/managed_record_runtime/output_wbtest.mbt
moon info --target js,wasm,native \
  src/local_tea src/managed_record_storage src/managed_record_runtime
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'public retained (watermark|window|dedupe|session)|Events record emission' \
  adapters/host-node/public-events-record-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
node scripts/check-local-resource-accounting.mjs
```

Selected interface generation compiled all three targets; this is not
Wasm/native test execution. Only local-node and run-host-core were rebuilt
from the restored source, with ignored bundles. Candidate receipts precede
commit creation; clean source-SHA checks and automatic Draft CI are reported
separately in the PR. No full Core, packed, proof or performance campaign was
run for this component.

At clean source `29deecb66f27f1ce2ee5df53a17934887a0c8373`, the same
JS selection passed 80/80 (`run-SIyiBs`, `focused-test-NuJBC7`) and the
public/gate selection passed 7/7 (`run-Xau31U`, `focused-test-6O3IXg`).
Subsequent edits to this record only clarify observation scope and attach
these receipts; they do not change the tested implementation or fixtures.
The runtime dependencies were rebuilt from the same implementation inputs.
Node Host and Workers read-only freshness checks and formatting passed;
their generated fixture sources needed no updates.

## Remaining boundaries

Operator field-name matching, key/Text comparisons and session identity
construction remain separate algorithmic scans. Atomic constructor/Bridge
record paths are not covered by these four kernel emission changes.
Preparation/schema lookup, JSON identifier normalization, runtime buffer
assembly, aggregate intermediate bytes and whole-Run physical accounting
remain distinct. These structural slot and cancellation fixtures are not
full Store fault/retry, packed Local/HTTP, Wasm/native execution or required
CI evidence. They do not replace the remaining Local completion work.
