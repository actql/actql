# Relation pipeline test retirement decision

Keep the four Host Stage tests which call `run_standard_host_values_sort_take`.
The generated `filter`/`select`/`sort`/`take` pilot does not currently establish an
equivalent replacement for any separable observation in this group. No test,
fixture variant or row/order assertion is removed. This decision is based on
source revision `d632998d8e7c3172f06e425b678d186f7ffbc51f`.

The purpose of consolidation is to reduce combination descriptions that people
must add, change and review when an operation or specification changes. Moving
the same fixture into a different syntax, removing assertions needed to observe
retained data, or counting generated cases as retired tests would not establish
that benefit. An assessment that finds no suitable replacement keeps the tests.

## Selected group

All four tests are in
[`local_managed_values_wbtest.mbt`](../../src/query_integration/local_managed_values_wbtest.mbt).
Their helper begins at line 564; the tests begin at lines 704, 709, 714 and 719.

| Existing test | Helper arguments | Distinct observation to preserve |
| --- | --- | --- |
| standard Host splits zero-input values from sort and take | `false, false, false` | Values, sort and take task splitting within the authored Stage |
| standard Host splits an indexed Relation Stage for two consumers | `true, false, false` | Retained input into a separate sort/take Stage |
| standard Host splits a unary Relation Stage for two consumers | `true, true, false` | Filter before sort/take in the separate Stage |
| standard Host splits a chain of bounded Relation Stages | `true, false, true` | A separate filter Stage feeding the sort/take Stage |

The fixture builder in
[`query_checked_program_wbtest.mbt`](../../src/query_integration/query_checked_program_wbtest.mbt)
uses nullable numeric `id` and nonnullable string `label`. It sorts `id`
descending with NULL last, takes the first row and feeds two retained consumers.
The consumers request opposite authored projection orders. The helper executes
the real Host dispatch and retained-input setup at quantum 1, then checks
independent consumer close and final ledger reclamation.

## Old observations and possible replacement evidence

| Old observation | Existing candidate evidence and its limit | Observation retained on the old route |
| --- | --- | --- |
| Sorted rows and associated payload, line 659 | The independent sort oracle covers the reviewed numeric/NULL profile. It does not establish the old string-payload profile or Host Stage correspondence. | Exact sort rows and their order |
| Take selects the correct first row, line 662 | The literal take descriptor supplies an independent skip/limit oracle and order precondition. Its executed numeric cases do not certify this Stage output. | Exact take row and payload |
| Each consumer receives the intended row and projection, lines 665 and 668 | The generated selected-provider path checks its own exact producer connections. It does not execute the retained Host fan-out. | Both consumer row assertions, including authored column order |
| Closing one consumer preserves the other and the producer, lines 671–681 | Conditional Session/chain models preserve cleanup responsibility under their stated premises. They do not replace actual Host/Store custody observations. | Close, availability and the preceding row assertions needed to identify the transported data |
| Shutdown releases reservations and holdings, lines 693–699 | Model cleanup responsibility is distinct from physical ledger reclamation. | Original shutdown and all three zero-ledger assertions |
| Stage segmentation connects the correct retained producer, lines 580–650 | The generated adapter correspondence covers `prepare_local_compute_module` and the selected Relation chain, not these four Host dispatch layouts. | All four fixture variants and their input/output observations |

Availability alone would still pass with an empty, stale or wrongly projected
consumer output. Thus the consumer row assertions are part of the custody and
connection observation, even though they also check semantic values. This group
does not provide a demonstrated separable duplicate that can be removed while
preserving those observations.

## Profile and corpus check

The [existing pilot](../relation-pipeline/README.md) admits exactly the numeric
fields `extra`, `k` and `tag`, with only `k` nullable and bounded integer values.
Its [observation harness](../relation-pipeline/harness.mbt) also observes only
numeric/NULL cells. Renaming a scope or a case does not certify the old schema,
string payload or execution route.

This executable admission check uses the old input shape and sort/take arguments.
Run it from the repository root:

```sh
node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import { inspect } from './proofs/relation-pipeline/engine.mjs';
import { registry } from './proofs/relation-pipeline/registry.mjs';
const legacy = {
  id: 'legacy-profile-check',
  rows: [
    { id: 'r0', values: { id: null, label: 'none' } },
    { id: 'r1', values: { id: 1, label: 'one' } },
  ],
  steps: [
    { id: 'sort', op: 'sort', args: { field: 'id', dir: 'desc', nulls: 'last' } },
    { id: 'take', op: 'take', args: { count: 1, offset: 0 } },
  ],
};
assert.throws(() => inspect(legacy, registry), { message: 'Outside row domain' });
console.log('Legacy profile is outside the reviewed generated domain');
NODE
```

This checks construction eligibility; it is not a production execution receipt.
The existing seed's `pair:sort/take` case sorts nonnullable `extra`. Its presence
does not by itself establish nullable-key placement, downstream surviving ties,
or retained transport. Deterministic cases inside the approved numeric domain
could improve those numeric observations, but cannot alone close the profile and
route gaps above. No supplement is added merely to obtain a deletion count.

## Mutation and guarantee limits

The existing `handoff-wrong-port` and `stable-tie-reversed` mutations demonstrate
their recorded generated-path mismatches. They have not been run as a paired
old-test/replacement comparison for this group. The old fixture's distinct sort
keys are not a stable-tie witness. Neither an unrelated tie inversion nor a
corpus-wide connection kill establishes replacement of the retained payload and
Stage observations. No mutation equivalence is claimed.

No observation is transferred, so no new mandatory-corpus acceptance or removal
gate is introduced. A future transfer would require concrete executed predicates
for the old obligation, independent scope/target/receipt binding and detection
of the relevant old-test error. Obligation labels or adjacent-pair counts would
be insufficient. This is a prerequisite for a future decision, not an approved
expansion of this pilot.

The existing conditional Lean model proofs and finite adapter/chain tests remain
distinct evidence. This assessment adds no formal instance or implementation
refinement. Child/runtime capacity bounds, the 256-byte allowance, delayed-stop
work, arbitrary DAGs and physical memory remain outside its guarantee.

## Consolidation outcome

Tests retired: **0**. Source lines deleted: **0**. Handwritten combination
descriptions removed: **0**. Human maintenance/review reduction established:
**none**. The original paths still execute, so **no CI time reduction is claimed**.
The remaining work per operation still includes its meaning and boundaries,
capacity assumptions and real-route connection/custody acceptance.

Closing the identified gaps would require same-profile implementation
correspondence and a genuinely separable old observation with a useful maintenance
benefit. The scope is not widened to create a retirement count. Historical
baseline and take-registration measurements remain unchanged.
