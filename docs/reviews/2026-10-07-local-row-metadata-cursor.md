# Bounded Relation row metadata preparation

Branch: feat/local-row-metadata-cursor. Initial implementation parent: #700
at `de990aa851ce0fbdd0b88b53c6446d3fc2748c2f`. The unmerged parent remains an
explicit dependency. Final integration target is main, not the parent branch.
Adopted origin/main: `8a9d39eddff6240868517daaf645d2a5d8e43ed7`, by normal
merge. The sole Graph transition at
`b98a50ff763d1367e344fdfa8aea380ec8749132` remains an ancestor; no old alias,
identity reinterpretation or compatibility fallback is introduced.

## Counterexample and implementation

The existing checked producer-read fixture with a 256-unit column name built
all input name entries before its first resume. The assertion that start
retains an empty input-name array failed 0/1 before the change
(`run-Lh3kAy`, `focused-test-vxKYJM`). It now passes.

The existing BoundedBindingRows owner prepares input names, output names and
cached cell sources through three resume phases. Each name is borrowed by
index from its already admitted schema. Binding and projection spellings use
the existing virtual-qualification UTF-16 comparator, at most 64 code units
per comparison transition. Input-column lookup borrows the checked schema and
retains one cursor slot, released once on completion or stopped cleanup.
There is no new name resolver, evaluator, scheduler or ledger.

This applies to SnapshotMap, OrderedBindings, Filter, AssertAll and Select
when metadata is wide or has long names. Select also covers the already
lowered rename/drop projection shape. Reverse binding search preserves the
former last-binding-wins rule. The additive immutable projection accessor
preserves checked authority without copying the full projection array.

Existing metadata reservations remain in force before construction; cached
sources retain the previous additional output-width reservation. Metadata
preparation changes resume granularity, not the existing logical work rule.
Temporary lookup workspace is independently admitted. The existing bounded
small-metadata lane retains its short-row budget footprint. Stop cleanup
clears partially prepared arrays and cursor state but retains input custody,
spent work and the existing output cleanup owner.

## Evidence and connection

- Lookup: qualified left/right spelling, supplementary Unicode, composed
  versus decomposed spelling, absence, one-slot/zero-slot admission and
  idempotent release. Schema identifier admission is not relaxed.
- Checked producer-read: cancellation during input-name preparation,
  output-name preparation, long binding comparison and long input lookup.
  A long authored binding is used to reach the comparison boundary.
- Select: cancellation inside output-name comparison, before input Value
  charging; input custody remains valid after stopped cleanup.
- Quanta 1/7/256: independent expected Number cells, identical control work,
  logical work and peak workspace for both derive and Select, with zero live
  workspace after cleanup.
- Indexed projection: existing checked lowering caller verifies authored
  order, negative/out-of-range indices and independence from a cleared
  defensive array copy.
- The resource gate requires each common metadata fixture. Removing any of
  their evidence roles rejects the affected completion record. The existing
  real-Store nine-field Values -> derive -> select Program reaches this
  shared owner; its three explicit Named Results, request reuse and
  delivered post-progress cancellation are reused, not duplicated per name.

The integrated focused JS batch passed 124/124 (`run-LS1tTL`,
`focused-test-N6YhOz`). A preceding batch passed 122/124: two new Select
fixtures incorrectly requested an expression context for an expression-free
projection. The fixtures were corrected to use its proper empty context
list, without bypassing checked Program preparation or changing expectations.
The current-source runtime build completed (`run-plclGt`). Final committed
source checks and public boundary receipts are recorded in the PR.

## Remaining boundaries

This does not finish all Local execution or all start transitions. The
defensive KernelBody copy, other kernel metadata (sort/key/JSON/window),
availability validation and the installed wide projected-read ceiling remain
separate. Initial BoundPrepared/producer preparation is not certified by
this cursor. #677 and its Native physical capacity review are independent.
No heap upper bound is inferred from logical workspace slots.

Only the selected JS and checkout Host boundaries are verified here. Full
Core, Wasm/native execution, packed Local/HTTPS, stop-latency measurement,
performance and full retained-history campaigns were not run. Hosted CI and
main adoption are separate from local success; no CI retry is requested.
