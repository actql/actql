# Stepped Events/Vectors record projection

## Completion unit

Required record schemas now use the existing AdmittedOutputRow cursor in
Events/Vectors-to-Relation projection. The shared owner initializes one
indexed pending cell per poll, borrows each source FieldName, and binary
searches the admitted schema with the existing 64-unit reference comparator.
It does not flatten or hash the pending name. Qualification and exact spelling
remain distinct from Graph field-role case folding.

The shared row cursor retains value recheck and logical measurement through
each yield. Control work remains cumulative; record progress follows commit.
Input operation binding, physical contract matching, input availability,
output identity and completion admission remain unchanged. Stop retains the
row cursor, input and unfinished output. Cleanup releases the row cursor
before cancelling the output builder and is once-only.

Matched cells reserve schema width. Borrowed root/name/recheck custody reserves
`max_depth+3`; the remaining existing workspace allowance is passed to the
shared row owner, which admits its row scope and measurement frames. No new
ledger, limit or public contract is introduced. OutputRowWorkspace maps to
the existing RelationOutput(CaptureLimit) cause.

Vectors delegates through start_records_to_rows to the same execution and
cleanup owner. Its vector-specific result and logical-limit regression remains
separate. Shared large-value evidence proves that common input/row discipline,
not independent public large-value Vectors acceptance.

## Independent resource and stop coordinates

The large record contains id 1, time 12, 8193 payload characters and an unused
Array of 129 numbers. Projection must preserve all four values.

- Setup: four initialization/source/verification polls, eight binary probes
  and one cursor start = 21.
- Row loading/recheck: 400; charge start: one; names/scalars/commit: seven;
  Text measurement: 131; Array measurement: 260. Total control work: 820.
- Logical output: row root plus 133 value nodes = 134, name bytes 35 plus
  payload bytes 8193 = 8228. Logical work: 8362, one-short 8361.
- Workspace: matched cells four plus custody thirteen, row scope five and
  Array measurement peak two = 24, one-short 23.
- Cancellation coordinates 32/256 lie within Text/Array recheck, and
  500/768 within Text/Array logical measurement. The paired 820-poll fixture
  fixes these coordinates and rejects collapsing the work into nominal polls.

Quanta 1, 7 and 256 preserve output and total work. Logical/workspace shortage
keeps the existing CaptureLimit cause; those tests isolate their allowances
instead of claiming a new public error distinction.

The four-number, 513-unit-name fixture derives 60 control polls: setup 29 and
row cursor 31. Logical output is five nodes plus 539 name bytes = 544;
workspace is 23. Control 59 and workspace 22 fail. Cancellation coordinates
16 and 50 occur in input-name matching and output-name measurement.

The existing small Events/Vectors fixtures keep logical node limits 14/13
and 10/9. Their continuation workspace is now 26/25 and 18/17, and control
work 134/133 and 50/49 respectively. The one-row Events fixture uses 66 polls.
These figures are derived from phase operations, not sampled successful runs.

## Ordinary public Host

The normal JSON Program uses Values, to_events, events projection and two
select consumers with the installed Local provider and real retained Store.
It reads exactly published, consumed_a and consumed_b, comparing complete
rows with the independent fixture. Repeated requests do not dispatch or
advance Compute again.

Normal planning separates this projection into task 2 after its Carrier
producer. Its first 256-work observation is inside the unused Array recheck:
setup 21, two scalar loads six and Text load 132 precede that Array. The
awaited Host fault hook delivers cancel at this coordinate without a sleep.
Snapshots remain held before physical-stop confirmation; afterwards no
unfinished Result is available, no extra dispatch/advance occurs and the
snapshot directory is empty.

The initial cancellation fixture incorrectly waited for the producer prefix
inside task 1, which had already completed. Its missed-barrier failure is
retained in run-gBKO4v, not reported as a product cancellation failure.

## Candidate checks and known failures

Base: 7d13324234cc33f06038a523c4b29e111854ab4a (PR #622, unmerged).

- The focused Events/Vectors caller batch passed 96/97 in run-CWqEQg;
  the new long-name fixture incorrectly rejected commit progress on the last
  Continue. Corrected shared fixtures passed 3/3 in run-NKTul6,
  focused-test-WKcr6t.
- Seven existing public Host cases and four targeted guard cases passed in
  run-gBKO4v; the new cancellation barrier failed as described above.
  Corrected public projection and guard cases passed 3/3 in run-vuxyUG,
  focused-test-va1FQy.
- The resource scan passes with unchanged totals: 69 operations, 62 mapped,
  seven typed pre-execution refusals, 62 full work/workspace records and
  114 path-scoped records. Full completion is not asserted by those totals.
- The Graph presence caller file passed 3/7 in run-1da3Ir. Reverting only
  this component's production change reproduced the same four work-boundary
  failures on the parent code in run-4us7Gf, focused-test-l4pa2R. That temporary
  comparison was restored before runtime generation. These are known parent
  failures, not passing Graph regression evidence.

Only local-node was regenerated for the public boundary. Its ignored
connectors_builtin_node runtime SHA-256 is
6a6f5b0c9e82adc19225c93a1f445438d5b912c4bb38fe14254d277458efbbe6.
This is checkout runtime evidence, not a pristine packed campaign.

Selected commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- --target js \
  src/query_integration/records_rows_bridge_steps_wbtest.mbt \
  src/query_integration/local_carrier_events_wbtest.mbt \
  src/query_integration/local_carrier_vectors_wbtest.mbt
node scripts/build-runtime-packages.mjs local-node
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-name-pattern 'public retained Events projection|record projections' \
  adapters/host-node/public-events-record-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
node scripts/check-local-resource-accounting.mjs
```

Full Core, Wasm/native execution, packed Local/HTTP, proofs, performance and
CI success are not claimed. Graph case-fold/name hashing and atomic output
append, including conditional presence rows, remain separate cursor work.
Common reference/JSON-key leaves, constructor/schema preparation, Events
comparison/session identity, aggregate intermediate byte admission and
whole-Run physical accounting also remain open. This is a component closure,
not full Local retained completion or a merge-ready declaration.
