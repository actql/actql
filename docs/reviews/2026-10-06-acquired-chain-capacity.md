# Acquired Relation chain scratch lifetime

Common-owner repair for #640 and the capacity counterexample in #509.
Reproduction baseline: `660c48375b782e4d2c3aa7b405caf17bf61915d5`.
The two reports were reproduced independently before identifying this shared
cause. Neither frontend branch is edited or adopted by this change.

## Independent before evidence

- #640: the saved Program from #639
  `57c5ce979025c57ac8d2dc65affaa9bedb83b0b7` was submitted through the real
  Embedded Local SDK/Host on the frozen main baseline. One Source acquisition
  completed; the expected-success assertion failed with
  `ACTQL_E_UNPUBLISHED_RUN` (`run-z7RnSU`, `focused-test-7XrWvW`). Its bytes are
  retained at `adapters/host-node/fixtures/acquired-distinct-join-limit.program.json`.
- #509: an isolated, clean snapshot of its actual submitted source
  `65d30aea83439d2217fb813747c01323b68fe1ef` independently reproduced
  `having-aggregate-property-alias-input-collision` (`run-UaLpWM`,
  `focused-test-oAltgq`). Its actual emitted Program was saved through a
  logging-only in-memory diagnostic, then submitted as JSON to clean frozen
  main. That expected-success assertion also failed (`run-PsxxjF`,
  `focused-test-nzTZS9`). The saved Program is
  `adapters/host-node/fixtures/acquired-having-alias-collision.program.json`.
- Separate diagnostics observed `LocalManagedStart -> Execution ->
  Physical(ExecutionLimit)` and the exact reservations below. Logging modified
  no package/runtime file, Program, limit, or expected result. These diagnostics
  are not pristine acceptance (`run-XTuF2b` for #640;
  `run-IlQfkn` and the saved-Program diagnostic for #509).
- A new focused capacity assertion failed before the repair, 0/1:
  `68,579,968 != 42,397,568` (`run-ogNFST`, `focused-test-kLViEs`).

The generated Programs are reproduction inputs, not independent lowering
oracles. Expected rows, ordered columns, nullability and acquisition counts in
the new Host test are independently authored from the handoffs.

## Cause and legitimate reservations

The old arithmetic correctly covered the implementation's live objects. The
chain kept every completed child execution until terminal parent cleanup;
therefore every child's scratch remained reachable and had to be reserved.
The unnecessary lifetime, rather than the 512 MiB admission ceiling, is repaired.

The existing successful binding-row, count/group and JOIN kernels already
detach accepted output from execution scratch. Their cleanup preserves that
sealed output. The common chain now confirms cleanup and drops both execution
references before advancing another child. All intermediate output handles,
shared input identities, external import custody and per-use logical budgets
remain owned. Pending/error cleanup cannot permit another child to start.
The last child remains owned until normal parent cleanup.

| Case | Before execution/scratch | After execution/scratch |
|---|---:|---:|
| #640, 9 steps / 3 fragment contexts | 546,445,568 | 226,624,768 |
| #509, 8 steps / 5 fragment contexts | 559,245,312 | 212,384,512 |

All values are bytes. Both retain the unchanged 14,240,000-byte output allowance,
1,000,000-byte transfer allowance and 536,870,912-byte execution ceiling. The
driver still reserves the output copy and 21,905,664-byte external import
allowance. Only eligible built-in-only chains use summed retained outputs plus
peak child scratch; unreviewed built-ins and family providers retain full-sum
capacity and reverse-order cleanup. This is not a measured RSS guarantee.

## Local verification

Using the repository's bounded, nonzero-test wrappers:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/connectors/local \
  src/query_integration/acquired_relation_branch_wbtest.mbt \
  src/query_integration/local_managed_unary_wbtest.mbt \
  src/query_integration/relation_chain_scratch_capacity_wbtest.mbt \
  src/query_integration/retained_execution_cleanup_wbtest.mbt \
  src/query_integration/local_retained_temporal_obligations_wbtest.mbt \
  src/physical_resources
node scripts/build-runtime-packages.mjs run-host-core local-node coordinator-core
node scripts/build-local-node-adapters.mjs
node scripts/local-checks.mjs test node -- \
  adapters/host-node/acquired-chain-capacity.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
node scripts/lowering-registry-vectors.mjs
node scripts/check-local-resource-accounting.mjs
```

The runtime preparation commands were executed inside the existing shared
bounded guard, serially. Precommit implementation-tree results: **72/72 Core JS**,
**12/12 real Local/HTTPS cases**, and **233/233 accounting-validator tests**.
The actual read-only accounting inventory and generated contract check pass.
The PR records separate final-commit receipts; these earlier runs are not
relabeled as clean-SHA executions.

White-box tests forward actual child callbacks and assert cleanup execution plus
removal of both persistent roots. They cover Filter/Select, CountGroups, general
Group, a shared earlier JOIN input, cancellation between children, false/error
cleanup and retry, and conservative append-chain behavior. Existing exact and
one-short work/workspace tests retain their independent expectations.

Public cases cover both saved Programs, typed empty results and in-flight
cancellation on Embedded Local and trusted loopback HTTPS. They check Named
Result rows and full ordered schema, one acquisition, every source stream,
same-request/attach/read reuse, failed Result denial and temporary-file cleanup.
Receipts record HEAD, clean/dirty status, source/test/runtime SHA-256 and input
bytes. Local fixture files and failure receipts remain available for review.

The first public matrix was 8/12: expected rows succeeded, but the newly authored
Object descriptor omitted the required explicit `additional_properties:false`.
The corrected assertion includes the checked closed-Object field required by
`value_contract/encode.mbt` and existing checked ValueContract fixtures; it does
not remove a column or weaken a comparison. #509's original `collisionColumns`
also omits this field. Its owner must align that fixture with the existing
checked descriptor contract before final source acceptance; that branch is
unchanged here.

## Runtime identity and remaining boundaries

Executed on Linux x64, Node **24.21.0**, Moon **0.1.20260904
(94521db 2026-09-04)**, moonc **0.10.12+1634b282e (2026-09-07)**, and
`@duckdb/node-api` **1.5.5-r.4**. Source packages use their checked-in
`0.0.0-development` versions. Fresh checkout-built JS/runtime wrappers are the
tested boundary; this is not a new external five-tarball acceptance campaign.
The PR records exact final runtime digests separately.

Wasm/Native execution, full Core, full packed/frontend corpora, Cloud and the
new early-retirement path's formal refinement are unverified. The existing
TimeSeries proof pilot remains conservative; `proofs/relation-chain/README.md`
explicitly preserves the capacity/physical-allocation proof residual.
The #639 and #509 feature owners still need their unchanged intended source
corpora on the integrated repair, including #509's separate feature chain.
No budget increase, alternate evaluator/ledger, merge, rebase, base change,
conflict resolution, deployment, live-provider write or manual CI trigger.
