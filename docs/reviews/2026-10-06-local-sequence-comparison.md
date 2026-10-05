# Bounded Sequence comparison boundary

## Scope

The existing Relation Sequence kernel used synchronous complete-value
comparisons inside identity sorting, duplicate-ID checking, compound-key
sorting, and partition boundary detection. These walks were separate from
bounded predicate initialization and output value measurement. Long Text IDs
with a 256-unit common prefix reproduce a per-resume charge overrun at quantum
one before this change (`run-XMxu0s`, `focused-test-OarrNL`, 0/1 passed).

The kernel now retains one exact pair/purpose/column cursor and reuses the
existing complete-value Text comparator and stepped index sorter. Each compound
key term can yield without changing the pair. Complete-value byte charges and
UTF-16 ordering are unchanged across quanta. Small scalar comparisons retain
their existing lane. Two pending cursor slots are reserved before construction.
Cancellation keeps the caller's input and pending comparison reachable; cleanup
confirms the child sort's stop before releasing callback state. It does not
implement Host cancellation finalization, a new scheduler, or a new ledger.

No public API, schema, pin, settings canonicalizer, or stored-data format changes.
This depends on the existing comparison stack through #491. The parent must
reach main before this branch's base is changed; the eventual merge target is
main, not a dependency branch.

## Focused kernel evidence

`sequence_text_order_wbtest.mbt` reaches the actual checked/lowered kernel:

- Independent expected columns and three ordered matches, including a nullable
  second Text key and a supplementary Unicode character, at quanta one and seven.
  Cumulative control work is identical and polling has a finite bound.
- Whole-operation workspace 64/63, calculated from metadata, sorted indices,
  match positions, row construction and pending output measurement, not sampled
  from a successful run. One-short retains typed `Rows(RowLimit)`.
- An isolated production identity pair requires 515/514 control units (two
  257-byte operands plus one complete-value transition), and 34/33 workspace
  slots (32 metadata plus two pending handles). This is explicitly **not** the
  whole-operation work requirement.
- Cancellation inside the long comparison in all four phases, including the
  second compound key. Input/cursor/workspace stay live until confirmed stop;
  no output is accepted. Cleanup releases the reservation once, does not charge
  more work, and does not dispose the caller's input.

The pre-existing small-input 642/641 control-work and 58/57 workspace boundaries,
overlap/contiguity variants, empty input and global grouping remain selected.
The focused JS selection passed 32/32 (`run-PR1BNh`, `focused-test-T5BbKY`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/sequence_text_order_wbtest.mbt \
  src/execution_relation/bounded_sequence_match_wbtest.mbt \
  src/execution_relation/bounded_asof_join_wbtest.mbt \
  src/execution_relation/bounded_index_sort_wbtest.mbt
```

The submitting PR records the final clean SHA and its executed selection.
Local wrapper evidence remains under `_build/local-checks/attempts` and
`_build/focused-evidence`. These JS results are not Wasm/native, packed,
retained-history integration, or hosted CI evidence.

## Unconnected ordinary public route

The ordinary installed Host reproduction is retained separately in
[sequence-public-retention.mjs](reproductions/sequence-public-retention.mjs).
It has independently authored producer/two-consumer expectations, a real
retained Store, an authored total sort, and same-request reuse assertions.
It is **pending**, not connected to the passing release suite or counted as
public acceptance:

```sh
node scripts/local-checks.mjs test node -- \
  docs/reviews/reproductions/sequence-public-retention.mjs
```

The execution stops during ordinary preparation, before any Sequence Compute.
The public projection reports `SubmissionUnknown` caused by
`ClientHostFailure` (500). Temporary local inspection of the actual ingress
cause identified `CheckDiagnostic` -> `SourceView` -> `CapacityStageIssue` ->
`SequenceCollection(MissingApplication(1))` (`run-DzkwxZ`,
`focused-test-WpWbHe`, 0/1). That inspection was removed; the public error
contract was not changed. The runtime packages `local-node` and `run-host-core`
were prepared from the changed comparison source. Bundles remain untracked.

The existing standard Host conformance path supplies exact Sequence capacity
applications. The installed ordinary source-free preparation path does not yet
derive/pass that application. Its owner requires one for every Sequence step,
including unused steps. The next connection must provide the existing policy
and match/output claims to that owner, retain exact bindings and publication
provenance, then execute this same reproduction. Do not bypass coverage,
increase policy ceilings, fabricate a proof, or replace this with internal
dispatch success. This comparison change neither closes that public route nor
claims public-phase cancellation, fresh-process replay, or full Local completion.

D owns #465 Run cancellation finalization; A's separate fixed-SHA review was
posted there. This kernel unit does not duplicate or block D/H's corrections.
