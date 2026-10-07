# Bounded Named Result preparation

## Completion unit

Named Result projection lookup and stable ordering now resume within the
existing `CompletedResultRelationExportPreparation` owner. Previously one
mapping step copied/searched a projection, and one merge step synchronously
charged and compared all Text keys. The subsequent metadata handoff drained
the existing metadata owner before returning from that advance.

The new implementation keeps a typed reference lookup cursor and uses the
existing `BoundedRowComparison` for charging and comparison. It polls the
existing metadata owner after row-map transfer instead of draining it.
There is no replacement scheduler, comparator, publication owner or ledger.
Language, wire, CID and stored-data contracts are unchanged.

Production changes are in:

- `src/execution_relation/completed_result_rows.mbt`: reference-role checking,
  spelling lookup, charged stable merge, private map transfer and retirement.
- `src/execution_relation/completed_output_export.mbt`: pollable metadata
  handoff, revocation/reentry checks and cancellation before stream transfer.
- `src/relation_results/ports.mbt` and `src/relation_typing/types.mbt`:
  immutable indexed projection readers, avoiding a full projection copy.

Reference qualification is not erased by spelling comparison: unqualified
`left.s` and qualified left `s` remain distinct roles when matching checked
projection inputs. Flat source-column spelling lookup retains its existing
semantics. Projection order, resolved order terms and stable ties are unchanged.

## Independent boundaries and custody

`completed_result_rows_progress_wbtest.mbt` uses two non-NULL Text values with
1024 ASCII characters, one supplementary character and different suffixes.
Each Text occupies 1029 UTF-8 bytes. Source columns are `s,n`, and the Result
projects/orders `s`.

- Mapping work is exactly 5: projection search, binding, source visit, order
  term and source visit. A budget of 4 fails with the typed `Limit`.
- Ordering work is exactly 2067: two row indices, two scratch indices, four
  emitted indices, one comparison and twice 1029 bytes. The four emitted
  indices include the existing final width-two copy pass. A budget of 2066
  fails with `Limit`; the implementation does not omit or clamp that work.
- Row-map workspace is exactly 5: two row indices, two scratch indices and
  one order term. A limit of 4 fails with `Limit`. This is not a claim that
  five entries cover all metadata roots or process memory.
- Long reference names exercise independent mapping work of 7, including
  both source-column visits. Name traversal yields within one reference.

Quanta 1, 7 and 64 produce the same mappings, ordered values and total logical
work within finite fixture poll bounds. Cancellation inside left charging,
right charging and comparison clears private maps while leaving the completed
producer available. Cancellation after row-map transfer clears metadata roots;
no stream is issued. Successful finish transfers private maps once and retires
the old cursor references. Reentry and revocation are rejected before append
or transfer, without deleting the source owner's checks.

## Actual Host route

The new cases in
`adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs` use normal
Program preparation, the installed Local provider, real retained/publication
Stores and the existing Result transformation driver. The producer performs
Values, Filter and Select, with two separate consumer tasks. All three Results
explicitly order by Text `s`. The producer's full checked schema is maintained
across the task input edges.

The independent expected order is the entire array:

```text
[{id: 2, s: prefix + "a"}, {id: 1, s: prefix + "b"}]
prefix = 1024 copies of "x", followed by U+1F600
```

All three committed names must be exactly `published`, `consumed_a` and
`consumed_b`, and each is independently read through the committed index.
There is no unordered comparison or product-derived expected ordering.

A read-only fixture observation of the real comparison cursor schedules
cancellation after positive progress inside the common prefix. The observation
creates no alternative execution state. The actual bridge is advanced with
quantum 1 and its generated success/failure wrapper is preserved.

This cancellation happens during Result preparation **after all three Compute
tasks have physically completed**, not during Compute. The fixture checks that
the Result borrow is released only by the preparation cancellation, no committed
index is exposed, and the exact original abort reason survives both the durable
payload envelope's `primaryFailure` and `cause`. Cleanup releases retained
holdings, read buffers, execution reservations and publication reservations;
the Compute dispatch count remains three across cleanup. Existing separate
Compute cancellation and Store append/finalize fault cases remain covered.

## Source and verification record

Parent #898 is merged. Main
`2664bcf3203c42eafe0ca5919763dbe8ad081b40` was normally merged without conflicts
at `44a1af4ffb1d9857cc2909bc1663fad4360236bd`. The adopted main contains parent
integration `902e6acd33b50b62c91e471efe3fd95391454be1`; there is no unmerged
dependency. Current submission/Frontend/Graph changes are retained.

Focused commands use the pinned Node/MoonBit environment and the existing
bounded, nonzero-test wrapper. Build output is ignored, not committed.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/execution_relation/completed_result_rows_progress_wbtest.mbt \
  src/execution_relation/completed_output_export_wbtest.mbt \
  src/execution_relation/completed_export_preparation_wbtest.mbt \
  src/execution_relation/table_input_export_wbtest.mbt \
  src/relation_results/ports_test.mbt

node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node \
  src/connectors/duckdb/conformance

node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern 'retained Named Result ordering|retained row-file export|retained Values honors exact scalar|retained source-free Values chain retains responsibility' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

- Core source `eb6310e9fae807c02ca4e1ec0e2020990fd3d721`: JS **38/38**,
  `run-8kM4EU`, focused evidence `focused-test-2ebEh0`. Both consumed runtime
  roots built at this clean SHA, `run-SC6nGq`.
- Host source `47bcc68a2320fe557ca990f5a5472e0d0db4d14b`: Node **10/10**,
  `run-Vg3NV3`, `focused-test-doV0BH`. Only the JS test fixture differs from
  the runtime build SHA; compiled runtime inputs are identical.
- Integration source `44a1af4ffb1d9857cc2909bc1663fad4360236bd`: both consumed
  roots rebuilt successfully, `run-rEHdUB`. The two new Host cases passed
  **2/2** with the narrower pattern `retained Named Result ordering`,
  `run-EwpP6R`, `focused-test-pYLNHr`. Node Host fixture freshness and
  `git diff --check` passed. The three changed core packages are unchanged
  from the recorded core SHA; earlier results are not relabeled as a new run.

The two new implementation APIs were generated with `moon info`; changed
MoonBit files were individually formatted with the pinned formatter. Focused
attempt logs are retained locally under `_build/local-checks/attempts` and
`_build/focused-evidence`. The subsequent record commit changes documentation
only; it is not a new test execution or a new packaged artifact.

Earlier failures remain separate evidence. `run-9lWc5a` passed eight existing
Host cases but rejected the new narrower producer Result contract during task
compilation, before Compute. The normal full-schema route is used for this
unit; that narrower inter-task projection is not claimed as supported here.
`run-OugMYl` then exposed an incorrect fixture assumption that the generated
bridge directly returned Bool. `run-6Orq3X` passed success but caught the
fixture comparing completed task records with bare integers. These fixture
corrections preserve typed return values and independent task identities.

The first core boundary attempt used 2065 for order work and failed. Reading
the existing merge algorithm showed its final width-two copy pass adds two
emissions, giving the independent formula 2067 above. The budget was not
replaced by a successful execution's measured total, and the one-short refusal
is retained.

## Remaining boundaries

Publication schema identity still calls `identify_relation_schema` atomically
inside metadata preparation. This recursive contract/name emission is not made
interruptible by polling its surrounding owner. Direct non-transformed and
managed-import convenience publication callers can still drain preparation;
this unit proves the existing asynchronous Result transformation route only.

Snapshot getter copies, physical chunk admission, blocking Native consumers,
trusted callback latency and allocation/GC wall-clock behavior remain separate.
The narrower inter-task Result projection rejected above also needs its own
checked connection work, not relaxed contract matching.

Not executed here: full Core, Wasm/Native tests, pristine packed/HTTPS, proof or
performance campaigns. Hosted CI for the submitted HEAD is reported separately;
Draft preparation is not merge verification. This closes one retained Named
Result preparation unit, not the whole Local Compute goal.
