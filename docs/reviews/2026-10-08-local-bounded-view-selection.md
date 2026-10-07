# Bounded managed selection preparation

## Product boundary

The existing managed selection owner now polls row-map copying, occurrence
validation, permutation duplicate checks, column aggregates and packed index
copying. The blocking convenience entries drain this same cursor; they do not
maintain a second selection or measurement algorithm.

The selected DuckDB managed-column strategy begins this preparation after native
settlement, yields through the existing Host polling helper, transfers its
selection once, and then uses the bounded View finisher before retained Store
sealing. Fixed filter selections retain strictly increasing occurrences.
Unsorted take retains a virtual exact slice, comparing actual native occurrences
without allocating an unnecessary row map. Sorted take retains its actual
permutation and existing uniqueness checks.

This branch starts from #872 at
`b17b183784d71e2e4c3bbf2f85324146ed16496f`. Its final target is main; maintain
the parent review base while that dependency is unmerged.

## Custody and accounting

- The preparation cannot issue a receipt, retain content or complete a task.
  Installed actual-execution verification and exact input/output bindings remain
  mandatory after selection transfer.
- Row/cell capacity and existing logical work are checked without a row-sized
  begin pass. Successful preparation preserves the original charge formula:
  index cells, copied row map, occurrence checks, column checks, aggregate
  visits, and the additional duplicate pass for permutations.
- Traversal quantum is separate from logical work. It does not reset the
  budget or change aggregate bytes/nodes, NULL facts, source order or typed
  limits. Unsupported computed-column diagnosis follows full aggregate checks,
  preserving earlier budget failure precedence.
- Already copied rows cannot be changed through the caller's original map.
  A changed pending width is refused. Every poll checks input availability.
  Reentrant advances/claims cannot steal the active cursor.
- Cancellation/revocation discards owned row maps, summary roots and partial
  copied indexes, not the borrowed source index or its Store lease. Transfer
  consumes the cursor once and leaves an independently owned selected index.
  Logical cancellation does not establish physical stop or cleanup completion.
- The product adapter retains its cursor in a `try/finally` and cancels partial
  preparation on failure, then uses its existing task/Store cleanup owner.
  No new scheduler, ledger, retry progression or execution proof is introduced.

## Independent boundaries

A wide checked derive copies the numeric source field into 100 extra fields.
The two authored source rows contain `n=1,s="é"` and `n=2,s="😀"`.
Its 102-column selection requires 204 cells and exactly 514 logical work:
204 cell copies + 2 row-map copies + 2 occurrence checks + 102 column checks
+ 204 aggregate visits. Preparation takes 726 cursor traversal steps at quanta
1/7/64, not an amount inferred from a successful product measurement.

Work 513 and capacity 203 refuse with `Limit`. Cancellation/revocation at six
intermediate positions leaves the original four source cells intact and clears
partial copies. Additional fixtures cover permutations, repeated occurrences,
empty selection, mutable maps, exact virtual slices, reentry and callback
cancellation. The independent one-row slice requires work 7 and 18 traversal
steps without a copied row map.

The actual DuckDB/real-Store caller exercises the query selection bridge,
Host-yield cancellation before transfer, repeated-claim rejection and expected
retained rows. Existing NULL/text, completion, consumers and final reservation
checks remain intact.

The installed strategy fixture executes a 50-row five-column group followed by
the supported filter/select consumer. It actually calls the product strategy's
new selection polling entry, reads its retained output through an exact
downstream binding and compares 50 independently authored expected rows.
Unchanged values have zero readmission and 250 reused measurement cells.
Cleanup preserves the source and checks that native attempts do not increase.
The existing computed-output pending cleanup/retry assertions remain required.
This uses ordinary Program preparation and opaque checked task fixtures; it is
not pristine packed Named Result acceptance.

## Focused preparation evidence

Commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/execution_relation/managed_selection_preparation_wbtest.mbt \
  src/execution_relation/managed_view_selection_wbtest.mbt \
  src/execution_relation/managed_row_measurements_wbtest.mbt \
  src/execution_relation/managed_computed_view_wbtest.mbt \
  src/execution_relation/managed_view_finish_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  adapters/connectors/duckdb/node/test/managed-compute-host.test.mjs \
  adapters/connectors/duckdb/node/test/managed-driver-reclamation.test.mjs
```

At the parent HEAD plus the implementation diff:

- The first compilation attempt failed on loop syntax:
  `run-bkCNHM` / `focused-test-dM621D`; no test success is claimed.
- Corrected focused JS selection before two final regressions: 25/25,
  `run-G9PZc6` / `focused-test-mYIvST`.
- Actual Store/query caller: 1/1 top-level matrix,
  `run-wVBu3H` / `focused-test-0lSKOG`.
- Installed strategy diagnostic failures are retained under `run-GSRKhA`,
  `run-59yaQA`, `run-8bXpWx` and `run-GQ4lva`. A newly added pure-select
  candidate was outside that registered provider's existing supported shape.
  Finally cleanup initially masked this cause; its existing pending owner is
  now retained and drained. No pure-select support is claimed or forced.
- Corrected supported filter/select product path: 1/1,
  `run-EuGMD3` / `focused-test-aW07AD`.
- One automatic permission-review timeout did not launch a test; it is not
  a test failure, live process or passing execution receipt.

Attempt IDs resolve under `_build/local-checks/attempts` and
`_build/focused-evidence`. Runtime preparation builds only the consumed
DuckDB Host/conformance checkout roots. The installed Program-preparation
module is reused locally; no packed artifact is produced or claimed.

## Remaining scope

Packed index allocation remains a single bounded-capacity allocation after the
aggregate checks, not a wall-clock-bounded allocation cursor. Dynamic array/map
allocation and collector latency also remain unproven. View-plan construction,
trusted availability/occurrence callbacks, physical chunk admission, Local
row-file finish and other blocking callers are separate boundaries.

Full Core, Wasm/Native core execution, packed/HTTPS, performance and proof
campaigns are not run for this unit. The known unchanged-main actual-history
failure from #866 is preserved, not independently repaired or bypassed.
Final-head hosted CI is unverified while this dependency PR remains Draft.
The whole retained Local goal is not complete.
