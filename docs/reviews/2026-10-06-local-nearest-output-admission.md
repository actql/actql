# Retained nearest: resumable output admission

## Owner boundary

This follows [nearest identity scanning](2026-10-06-local-nearest-key-scanning.md).
Output identity construction, contract rechecking and row measurement previously
ran synchronously inside one emission. This unit partitions output admission,
not another operator comparator or Run cancellation controller.

[The shared row cursor](../../src/execution_relation/admitted_output_row_steps.mbt)
borrows the existing output, runtime recheck and logical row-charge cursors.
It reserves the provisional row before reading, then holds the original buffer
exclusively across yields. Each advance reads one cell, advances one recheck
poll or advances one logical-charge poll. A row commits only after its charges
succeed. The cursor cannot finish a task, seal numeric slots or publish Results.

Failed custody remains held until the caller's stopped Session invokes cleanup.
Cleanup discards all unpublished rows, clears traversal frames and the read
callback, and releases its scope once. Successful row cleanup leaves accepted
rows under the original owner. Conditional-presence schemas are explicitly
rejected by this required-column cursor, not coerced to NULL.
Delayed cleanup of a completed row cannot unlock a later provisional row;
that ownership boundary has its own regression.

[Nearest](../../src/local_veca/nearest.mbt) drives the cursor with its existing
Session. Composite identities use the existing object builder, one component
per transition in the target contract's canonical order. Input-reading identity
scratch is reused for provisional output identities; those phases do not
overlap. Eight additional structural slots cover the four-field row and its
traversal frames. Values retain their separate logical output budget. These
structural reservations are not heap-byte measurements.

No scheduler, ledger, Run state machine, identity preimage, Store format or
provider-selection rule changes. D's cancellation integration and H's
Effect/Ledger repairs are not edited or prerequisites of this unit.

## Independent bounds and counterexample

The shared single-row fixture has three nodes, names `n`/`s` and a 128-byte
Text: **3 nodes, 130 text bytes, 133 logical work**. Four temporary slots
succeed; three fail during measurement and two fail before reading. Logical
node/text/work one-short limits preserve `CaptureLimit`. Partial rechecking
and measurement retain custody until cleanup and release it once. Existing
bounded output-import tests execute alongside this cursor.

For the two-by-two nearest fixture with 129-code-unit identities:

- Input preparation remains 1078 control units.
- Each query costs two score slots, six fold units, 133 tie-sort units and two
  39-unit output rows: 219. Final completion costs one.
- Total control **1517/1516**, structural workspace **44/43**. Quanta one,
  seven and 256 preserve cumulative work and independently authored rows.
- Each output has five nodes, 29 name bytes and 258 identity bytes. The exact
  output allowance is **20 nodes, 1148 text bytes, 1168 logical work**.
- Numeric single-record nearest changes from 28/27 control and 23/22 workspace
  to **52/51 and 31/30**, reflecting actual output transitions.

The composite fixture fixes twelve positional components in canonical order
`0,1,10,11,2,3,4,5,6,7,8,9` with their original numeric values. It checks
quantum-invariant work, not an independently derived composite work cap.

Cancellation barriers interrupt Text rechecking, logical charging and the
next row after one row commits. Cleanup before confirmed stop remains
`NotStopped`; cancel request is not physical stop. Borrowed inputs remain live.

The public-quantum core fixture uses 661-code-unit identities. Its totals are
5334 input units, 673 scoring/tie-sort units per query and 71 units per output.
The first row ends at 6078; quantum 24 ends at **6144** inside the next row's
logical Text charge, with progress one.

Substituting the unchanged parent nearest implementation from
`e515b3f8e019dd02e48150beda3381e9ea45b26b` made this regression fail **2 != 1**
(`run-hwLCA7`, `focused-test-Go3umx`). Both output rows were hidden inside
atomic emissions. The changed implementation was immediately restored; the
final focused selection succeeds without weakening that expectation.

## Ordinary retained Host

[The installed Host harness](../../adapters/host-node/public-nearest-key-retention.test.mjs)
uses ordinary Values, two explicit `to_vectors` bridges and nearest in their
selected fused path. A real retained Store publishes producer and two consumer
Named Results against independent ordered expectations. Resubmission adds
neither dispatch nor Compute advances. The existing awaited observation hook
supplies the core-certified 6144-unit barrier, without sleep or task splitting.

Public cancel persists a request while stop is unconfirmed. Snapshot files
stay unchanged at the barrier. After release, stop is confirmed, all three
Results stay unavailable and snapshots are reclaimed without more Compute
advances or dispatch. File reclamation is not a complete holder/reservation
census; core fixtures separately establish input and temporary-scope lifetimes.

An initial 2049-code-unit public diagnostic failed before the target barrier;
it is not output-cancellation evidence. The final fixture reaches that boundary
under the unchanged installed profile. No product limit was raised. Earlier
composite/Text fixture errors likewise are not product-defect evidence.

## Focused validation

Checks use changed working-tree source descended from the parent SHA above,
not clean-HEAD packed acceptance or an all-target campaign.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/admitted_output_row_steps_wbtest.mbt \
  src/execution_relation/bounded_admitted_output_wbtest.mbt \
  src/query_integration/nearest_text_scanning_wbtest.mbt \
  src/query_integration/nearest_typed_entry_wbtest.mbt \
  src/query_integration/nearest_composite_output_wbtest.mbt
node scripts/local-checks.mjs test moon -- --target js \
  src/query_integration/local_carrier_vectors_wbtest.mbt --filter '*nearest*'
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-nearest-key-retention.test.mjs
```

- Core: **18/18**, `run-rvJbMu`, `focused-test-q8VRfk`.
- Existing callers: **23/23**, `run-Wjm0ZH`, `focused-test-U1ANd7`.
- Final regenerated installed Host: **2/2**, `run-ELje20`,
  `focused-test-ToSCty`. Runtime freshness, changed MoonBit formatting and
  `git diff --check` passed.
- API regenerated with `moon info --target js src/execution_relation`.
  Only `local-node` was rebuilt; runtime bundles stay ignored.
- Resource gate and operation index: **208/208** (204 + 4), `run-TeGU7z`,
  `focused-test-NhT75C`. The read-only resource audit passed.

The resource gate requires output-specific operator, shared cursor and actual
public-suite evidence. Missing roles are mutation-tested; shared-profile
success does not substitute for these boundaries.

Not executed: Wasm/native, full Core, packed/HTTP, proof campaigns, performance
or wall-clock stop measurements, new Store-failure campaigns and D's restored
Model cancellation acceptance. Ranking comparisons and other synchronous scans
remain separate. Local retention as a whole is not complete. The final merge
target is main, after the nearest scan/Pool parent stack reaches main.
