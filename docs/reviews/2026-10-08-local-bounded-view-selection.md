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
`b17b183784d71e2e4c3bbf2f85324146ed16496f`. That dependency is now merged.
The adopted main is `04b1e822091b3b02fded57e88d13591d0e5dfa29`, incorporated
by normal merges. This unit targets main with no unmerged parent dependency.

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
DuckDB Host/conformance checkout roots. After main integration, the changed
installed Program-preparation module was rebuilt from integrated source:

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node
```

No packed artifact is produced or claimed.

## Fixed-source integration evidence

The final verified source is
`2ae09d66393fc08835725a392e54034b9203fde0`, with a clean worktree for each
test. The commands above completed with complete output and released locks:

- Focused JS: 27/27, `run-KdP0Xi` / `focused-test-Ad9Q4E`.
- Actual DuckDB/Store callers, serial: 2/2 top-level cases,
  `run-hEQoDl` / `focused-test-HMQmnP`.
- The eight affected MoonBit files match the pinned formatter. The first
  final formatting comparison found noncanonical layout; the formatter-only
  changes were committed before these fixed-source tests.

The earlier integrated source
`1b8d0c668f61e9b4536652c13e1c6a8ed616dbf9` was also checked cleanly:

- Program-preparation runtime build: `run-p1OWW2`, two compilation tasks.
- Focused JS: 27/27, `run-1vukcE` / `focused-test-tWQ4kl`.
- Actual DuckDB/Store callers, serial: 2/2 top-level cases,
  `run-6DTX3U` / `focused-test-EGVE0N`.

Earlier clean-source results remain attached to their original revisions:
`8be9697769f72cdf220547f3b907abd159bac500` passed 27/27 JS and 2/2 Node
(`run-Sns2Tk`, `run-WRmiGU`);
`e976945fbcfc360d97770a818ed6155312db1d3b` passed 27/27 JS and 2/2 Node
(`run-Nvgcyb`, `run-3BITAO`). These are not relabeled as final-source evidence.

Main's unknown-reference diagnostics and shared history normalization records
are retained. Integration removed an accidentally duplicated diagnostic test;
the diagnostic files match the adopted main and introduce no Local delta.
The historical #866 history failure is not repaired independently here;
main's shared fixes are adopted without bypassing or deleting declarations.
Actual retained-history verification was not rerun for this unit.

The subsequent evidence-only commit changes this report, not the verified
implementation. Submitted-HEAD hosted verification is recorded in the PR.

## Remaining scope

Packed index allocation remains a single bounded-capacity allocation after the
aggregate checks, not a wall-clock-bounded allocation cursor. Dynamic array/map
allocation and collector latency also remain unproven. View-plan construction,
trusted availability/occurrence callbacks, physical chunk admission, Local
row-file finish and other blocking callers are separate boundaries.

Full Core, Wasm/Native core execution, packed/HTTPS, performance and proof
campaigns are not run for this unit.
Final-head hosted CI is unverified while this PR remains Draft.
The whole retained Local goal is not complete.
