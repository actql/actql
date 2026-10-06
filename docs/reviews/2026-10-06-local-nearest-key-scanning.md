# Retained nearest: bounded typed identity scanning

## Operator boundary

Nearest previously called `compare_key_values` synchronously while validating
identities, sorting both inputs, checking adjacent duplicates and resolving
equal-score candidate ties. A long equal Text prefix was hidden inside one
control unit. This is operator scanning, not value measurement or Store copying.

[Nearest](../../src/local_veca/nearest.mbt) now borrows the existing
`value_admission.BoundedKeyComparison` across resumes. Each charged transition
advances one comparison unit; a pending comparison preserves its phase, pair
and component index. Identity validation also collects one component at a time.
The existing Session checks stop before the next transition and remains the
only execution and cleanup owner. No scheduler, comparator, wire contract,
identity preimage or task-partitioning rule is added.

The common cursor preserves typed non-null key admission, UTF-16 Text order,
decimal/reference checks and stable score ties. It borrows existing values,
without copying Text or introducing a new record buffer. Existing structural
workspace admission is unchanged; this does not establish a heap-byte theorem.
Cleanup clears the pending cursor, collected identities, records and scratch
once. Caller-owned input materials remain available after confirmed stop and
cleanup. Stop confirmation and cleanup are separate observations.

## Independent limits and counterexample

[The core fixture](../../src/query_integration/nearest_text_scanning_wbtest.mbt)
uses two reverse-ordered candidates and two reverse-ordered queries, each with
128-code-unit common prefixes and a distinct last character. Equal embeddings
produce tied dot scores of five. Expected rows are authored query-major, then
candidate `a`, `b`, with ranks one and two.

Independent control work is:

- Four records: four times (one identity slot + four field/match units +
  129 self-validation units + three component checks) = 548.
- Four scratch slots, two input sorts at 133, two uniqueness scans at 130:
  548 + 4 + 266 + 260 = 1078.
- Each query: two score slots + six fold units + 133 tie-sort units + two
  emitted rows = 143. Two queries and final completion: 286 + 1.

Total **1365** succeeds; **1364** fails with typed `NearestWorkLimit`. Quanta
one, seven and 256 preserve results and cumulative work. Structural workspace
is 12 input slots + eight score slots + six record scratch slots + two identity
slots + eight fixed slots = **36**; 35 fails with `NearestWorkspaceLimit`.
These are nearest control/structural limits, not whole-Run exact Ledger limits.
Expectations are not inferred from a successful execution's usage.

The unchanged product failed the new regression with **85 != 1365**
(`run-omz6z7`, `focused-test-mDrjLY`). Earlier fixture attempts included a syntax
error and an insufficient cumulative output-text allowance; they are not
operator-defect evidence. The scan counterexample uses sufficient output limits.

Cancellation barriers at units 40, 320, 450 and 1120 fall inside identity
validation, input sorting, duplicate detection and score-tie scanning, according
to the fixed phase totals above. Each rejects cleanup before confirmed stop,
preserves reported work and both borrowed inputs, and permits cleanup once.
A 513-code-unit identity fixture also fixes the public 256-unit barrier:
five field/control units precede self-validation, so that resume cannot finish
the first identity. Cancellation stops without output completion.

## Ordinary retained Host

[The installed Host fixture](../../adapters/host-node/public-nearest-key-retention.test.mjs)
uses an ordinary Program:

```text
candidate Values and query Values
  -> two explicit to_vectors bridges -> nearest (one fused task)
  -> producer Named Result and two consumer tasks
```

Authored Stage input order differs from operation-port order, retaining the
existing exact input binding. All three Result names are read explicitly and
compared with independent ordered rows. The Host reports retained-file output;
resubmitting the same request does not add dispatch or Compute advances.

After both bridges finish, the existing awaited Host observation hook suspends
the first nearest quantum inside the matching long-identity scan. Public cancel
persists the request while physical stop remains unconfirmed, no Result is
published and retained snapshot files remain unchanged. Releasing the barrier
confirms stop, leaves all Results unavailable and reclaims the snapshots,
without further Compute advances or another dispatch. The core fixture supplies
borrowed-input lifetime evidence. Snapshot reclamation is not a complete
holder/reservation census.

The initial public diagnostic used Pool's three-field bridge total rather than
nearest's two-field total. It failed the test hook, not product computation.
The fixed bridge total is independently two records times (two fields + commit)
= six. No routing, splitting or production budget was changed to fit the test.

## Focused validation

Validation ran on the working-tree source descended from
`368251fe0fa9eb98d4a84f49f7a62c4f2029c0c5`, before final commit. Evidence records
that parent and working-tree scope; it is not clean-HEAD packed acceptance.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_integration/nearest_text_scanning_wbtest.mbt \
  src/query_integration/nearest_typed_entry_wbtest.mbt
node scripts/local-checks.mjs test moon -- --target js \
  src/query_integration/local_carrier_vectors_wbtest.mbt --filter '*nearest*'
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-nearest-key-retention.test.mjs
node scripts/local-checks.mjs test node -- \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

- Core scan and typed Relation entry: 5/5 (`run-CycTNQ`,
  `focused-test-QVZV9F`).
- Existing nearest consumers: 23/23 (`run-YpdpWW`, `focused-test-PXrMRp`).
- Public retained Host: 1/1 (`run-MIBqAW`, `focused-test-lbGinc`).
- Resource evidence/index: 207/207, comprising 203 + 4 (`run-U1KpWE`,
  `focused-test-pUgGkG`). Missing long-key roles, the public case or its actual
  installation-suite import are rejected.
- Only `local-node` was rebuilt from the changed MoonBit sources. Runtime
  bundles remain ignored; its read-only freshness check passed. Resource audit,
  changed MoonBit formatting and `git diff --check` also passed.

Not executed here: Wasm/native, full Core, packed/HTTP, proof campaigns,
performance/stop-latency measurements, new Store failure campaigns or D's
restored Model cancellation acceptance. D's merged cancellation fact/revision
boundary was reviewed read-only, not independently re-executed or duplicated.

Nearest output identity reconstruction/rechecking, composite output encoding,
ranking comparisons and other synchronous operator scans remain separate work.
This unit does not claim complete Local retention or merge readiness from Draft
CI. Its parent Pool unit must reach main before retargeting this dependent PR.
