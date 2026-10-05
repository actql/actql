# Bounded DISTINCT admitted-value comparison

## Scope and counterexample

Whole-row DISTINCT formerly called the recursive complete-value comparator
inside one sorting or adjacent-row poll. A checked/lowered Object -> Array ->
257-byte Text fixture failed the quantum-one charge bound before this change:
0/1 passed (`run-RGOPpJ`, `focused-test-WZpbEB`). This is an operator-scanning
counterexample, not a retention measurement or public Run cancellation claim.

The existing row comparison cursor now retains the Set owner's admitted-tree
continuation for Array/Object/Vector pairs. Child frames reserve the existing
workspace before allocation; Text charging and UTF-16 scanning yield through
the existing cursor. A pending comparison does not repeat the enclosing logical
merge/adjacency charge. Scalar, flat Text, authored sort and keyed dedupe keep
their existing paths. No scheduler, ledger, comparison domain, public API,
schema, pin or canonical preimage changes are introduced.

Cancellation keeps borrowed input roots and pending frames reachable until the
bounded child confirms stop. Cleanup then closes the tree once and releases
workspace without disposing caller inputs. D's Run cancellation finalization
and H's Ledger close/value boundaries are not changed by this unit.

## Core evidence

The focused JS selection passed 99/99 (`run-l7pwNW`,
`focused-test-2qbNWG`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/bounded_distinct_tree_wbtest.mbt \
  src/execution_relation/bounded_binding_rows_wbtest.mbt \
  src/execution_relation/presence_whole_distinct_wbtest.mbt \
  src/execution_relation/bounded_set_nested_comparison_wbtest.mbt
```

- Quanta one and seven produce the independent two-survivor expectation in
  first-occurrence order with equal cumulative logical work. A comparison poll
  at quantum one charges at most two units: one logical action and one node.
- Cancellation in sorting Text charging/scanning and adjacent-row scanning
  confirms `Stopped` before releasing pending frames. Repeated cleanup adds no
  work and releases no resource twice; the caller's input remains available.
- Whole-operation workspace is exactly 15 slots: four metadata slots, one term,
  six index entries and four tree slots. Fourteen fails with `Rows(RowLimit)`.
  Three comparison frames succeed; two fail with the same typed limit.
- The isolated row comparator accepts work 521 and rejects 520 with `Limit`:
  wrapper 1 + Object 1 + two property-name bytes 2 + Array 1 + Text node 1 +
  two 257-byte operands 514 + NULL node 1. This is a comparison-only work
  boundary, not an inferred whole-Run allowance.
- A separate fixture certifies that nine 256-work child quanta reach actual
  nested UTF-16 scanning, with an offset inside the operand. It is the public
  test's synchronization point, not a fixed sleep or assumed wall-clock bound.
- Existing scalar/keyed DISTINCT and absent-versus-NULL tests remain selected.
  Other row-comparator callers compile with an empty optional tree, but their
  complete suites were not executed by this selection.

## Ordinary retained Host evidence

[The public fixture](../../adapters/host-node/public-distinct-value-retention.test.mjs)
uses the ordinary installation, account authorization and real retained Store:

```text
Values -> DISTINCT -> derive array property -> Unnest -> select -> sort
  -> producer Named Result
  -> two separate consumer tasks and their Named Results
```

The producer is one fused task, not test-only task splitting. Literal expected
rows preserve both long distinct strings and two explicit NULL items. All three
Named Results are read and compared in order. Repeating the same public request
uses the same Run and performs no additional dispatch or Compute.

The cancellation case observes Values completion and child start, then blocks
the ninth full DISTINCT quantum. The matching core test certifies scanning at
that point. Public cancellation records the request while physical stop remains
unconfirmed; after the barrier is released, stop is confirmed, all three Results
remain unavailable, snapshots are reclaimed and neither Compute nor dispatch
is repeated. The fused Values input lives in the chain's completed-input owner,
not an intermediate Store snapshot. Core evidence checks its borrowed roots and
scratch directly. Empty public snapshots are not a whole-Ledger reservation
census or a claim about D's Model/Effect recovery.

The public DISTINCT file passed 1/1 (`run-ukCmoY`, `focused-test-QQAXlE`). The
same command initially failed the separate accounting suite because its new
cross-route source was absent from the immutable source snapshot; that loader
omission was fixed. The combined command is not reported as passing. Earlier
public test authoring assumed a separate DISTINCT task and missed the barrier;
the corrected synchronization follows the actual fused task without changing
production splitting or weakening its conditions.

The final focused Node selection passed 7/7 (`run-0sQEBt`,
`focused-test-xOhUzN`): public DISTINCT 1, existing public Set 2, and operation
evidence-index tests 4. It reused the same generated production runtime:

```sh
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-distinct-value-retention.test.mjs \
  adapters/host-node/public-set-value-retention.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

Only the consuming JS runtime packages were prepared from the changed source:

```sh
node scripts/local-checks.mjs build moon -- --target js --release \
  src/connectors_builtin_node src/connectors/duckdb/host_node \
  src/connectors/salesforce/host_node src/retained_host_bridge \
  src/process_host_bridge src/checkpoint_runtime_node src/client_values_host_abi
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
```

The scoped build passed (`run-aLgzan`). Runtime bundles remain ignored and no
tarball or pristine packed distribution campaign was produced. Tests executed
before committing the unchanged implementation tree; the PR records the exact
submitted SHA separately from local evidence identifiers.

## Evidence gate and source census

The production route requires five operation-specific comparison roles plus
the public retained fixture. Mutations remove each role and the real suite
import separately; each omission is rejected. The immutable input loader also
captures that actual suite source, rather than relying only on manifest names.

Resource gate tests and the finite capacity source-census unit tests passed
202/202 (`run-eWolVU`, `focused-test-GOSbZR`: 197 + 5):

```sh
node scripts/local-checks.mjs test node -- \
  scripts/check-local-resource-accounting.test.mjs \
  proofs/relation-pipeline/capacity.test.mjs
```

The exact state-field census had omitted three fields already present in the
parent: `input_logical`, `output_logical` and `output_recheck`. Their actual
source order is now recorded; no numeric model formula or unknown-field
rejection was removed. The optional tree is absent in the existing numeric/NULL
proof scope. Recursive comparisons have runtime reservations, but this update
does not prove nested-value heap bytes or execute the proof campaign. Existing
unresolved physical-allocation premises remain unresolved.

The actual resource accounting scan, Workers/Node Host fixture freshness,
changed MoonBit formatting, Node syntax and `git diff --check` also passed.
No tracked generated fixture or interface changed; runtime bundles stay ignored.

## Dependencies and remaining coverage

This branch depends on unmerged #513, then #510 and #506. Preserve the parent
base until those changes reach main; the eventual merge target is main.

Wasm/native, full Core, packed/HTTP, new Store failure campaigns, integrated CI,
public whole-Ledger reservation measurements and D's Model recovery acceptance
were not executed for this unit. Registered targets are not execution evidence.
Other synchronous recursive comparator callers and expression scans remain
separate work; this is not completion of all Local retained routes.
