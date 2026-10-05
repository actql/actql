# Bounded interval join Text comparison

## Boundary and change

The interval join kernel already bounded pair search and output measurement,
but `CompareKey` called the synchronous complete-value comparator. A checked,
lowered two-by-two fixture with 257-unit common-prefix Text keys fails the
quantum-one comparison bound before the change: 0/1 passed (`run-9sbexH`,
`focused-test-reH8BS`). This is a kernel counterexample, not measured public
Run stop latency or evidence of a wrong join result.

`bounded_interval_compare_key` now reuses the existing complete-value Text
cursor for operands longer than 64 units. The pair and key index stay fixed
while pending; the original input owners retain the borrowed cells. Two cursor
slots are reserved before construction and released after comparison completes.
Cancellation leaves the cursor and reservation reachable until confirmed stop
and cleanup. Repeated cleanup neither charges work nor disposes caller inputs.
Small comparisons retain the existing path. Logical byte work, UTF-16 equality,
NULL non-matching, pair visits, temporal membership and output order are unchanged.

This is comparison scanning, not value measurement or retention copying. It
does not change public API, schema, pins, stored values, Run cancellation
finalization, or the existing temporal algorithm. D owns the #465 Host boundary;
this change neither duplicates nor blocks that correction.

## Focused kernel evidence

The final JS selection passed 21/21 (`run-uasCyV`, `focused-test-qAh59V`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/bounded_interval_join_wbtest.mbt \
  src/execution_relation/bounded_asof_join_wbtest.mbt \
  src/execution_relation/sequence_text_order_wbtest.mbt
```

- The interval fixture finishes within a fixed polling bound at quanta one and
  seven, with independently authored ordered rows and identical cumulative
  control work. It includes equal keys and a long-prefix unequal key.
- Cancellation during operand charging and comparison scanning keeps inputs,
  pending cursor and workspace until `Stopped`. No output is accepted; cleanup
  releases scratch once and preserves input availability.
- An isolated production key pair has exact control 515/514 (one transition
  plus two 257-byte operands) and workspace 16/15 (14 metadata plus two cursor
  slots). This is explicitly not a whole-Run budget.
- The complete long-Text operation has work 2188/2187 and workspace 18/17 at
  both quanta. The work formula replaces four one-unit comparisons in the
  existing fixed 132-unit scalar fixture with four 515-unit Text comparisons:
  `132 + 4 * 514`. Comparison scratch peaks below the unchanged output peak.
  One-short fails with typed `Rows(RowLimit)` and no accepted output.
- Existing scalar exact/one-short, output, cancellation and cleanup tests remain
  selected. The production route inventory requires all four new roles; removing
  any one is rejected by the accounting checker regression.

## Ordinary retained Host evidence

[public-interval-retention.test.mjs](../../adapters/host-node/public-interval-retention.test.mjs)
uses the actual installed Embedded Local Host and real retained Store. The
ordinary Program has two Values producers, `interval_join -> sort`, and two
separate consumers. All three Named Results are read explicitly and compared
with independent ordered rows. Long Text keys match, repeated right matches
survive, an unmatched left key yields NULL, and NULL keys do not match. The same
request reuses the Run without another Compute advance or completion; temporary
carrier snapshots are reclaimed. The test is imported by the normal installed
Host suite.

The focused Node selection passed 2/2 (`run-8jaNcf`, `focused-test-Ox7KSS`):

```sh
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-interval-retention.test.mjs \
  adapters/host-node/public-sequence-retention.test.mjs
```

Only `local-node` and `run-host-core` were rebuilt from the changed production
source before this check. Bundles remain ignored. The Sequence case is an
unchanged caller regression, not a second interval case. The submitted PR records
the exact clean source SHA; these commands ran before committing the unchanged
production/test tree. The wrapper evidence remains under `_build/local-checks`
and `_build/focused-evidence`.

## Remaining coverage

Wasm/native execution, packed/HTTP acceptance, exact public-phase cancellation,
new Store failure injection and final integrated CI were not run for this unit.
Existing temporal Host fault evidence is not relabelled as a new comparison-phase
measurement. Registered three-target fixtures are not three-target execution
results. No all-Local completion claim is made.

The dependency is #502 on top of the unmerged comparison stack. Preserve that
parent base until it reaches main; the eventual merge target is main.

The missing-role checker regression passed 1/1 (`run-LWfXYo`,
`focused-test-r2Ti3n`) with:

```sh
node scripts/local-checks.mjs test node -- \
  --test-name-pattern 'interval join requires stepped Text' \
  scripts/check-local-resource-accounting.test.mjs
```

The real resource audit, Workers/Node Host fixture freshness, changed MoonBit
formatting, Node syntax and `git diff --check` also passed. No fixture output or
public interface needed regeneration; runtime builds are ignored as before.
