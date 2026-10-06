# Retained Pool: bounded typed key scanning

## Boundary and implementation

Pool previously called `compare_key_values` synchronously in key validation,
identity sorting, duplicate detection, group sorting and group boundaries.
Yielding once per comparison did not bound a long equal Text prefix. This is
operator scanning, not value measurement or retained-output copying.

[Pool](../../src/local_veca/pool.mbt) now retains the existing
`value_admission.BoundedKeyComparison` across resumes. Each Pool transition
advances one comparison unit and checks the shared stop reader before the next
unit. The current phase, record pair and key index do not change while the
comparison is pending. The same common comparator preserves typed ordering,
UTF-16 order, decimal/reference checks and non-null key admission.

The fixed cursor borrows already admitted keys; it does not copy strings,
allocate another record buffer or introduce a new value root. Pool's existing
structural slot reservation remains unchanged. This is not a new heap-byte
capacity theorem. A private state alias permits ownership fixtures to inspect
the cursor; the bounded Session remains the only execution/cleanup owner.

Cancellation is a request, not confirmed stop. Pending keys and partial output
remain owned until the Session reports `Stopped`. Its cleanup clears the
comparison, collected keys, records, sort scratch and unpublished builder.
The caller's borrowed producer read stays available. The second cleanup returns
`false`, confirming no repeated reclamation. Numeric folds, output-builder
accounting, schemas, identity preimages and Model/Run cancellation are unchanged.

## Independent bounds and pre-fix counterexample

[Core fixtures](../../src/local_veca/pool_text_comparison_wbtest.mbt) use two
reverse-ordered records with 128-code-unit common prefixes and different final
characters in both group and identity keys. The independent control total is:

- Input admission: two times (12 field/control units + 129 group units +
  129 identity units + two vector components + one collected record) = 546.
- Sort scratch: 2.
- Identity sort: 129 comparison + one drain + two copies = 132.
- Duplicate checks: 129 comparison + one phase transition = 130.
- Group sort: 129 comparison + one drain + two copies = 132.
- Group boundaries: 129 comparison + two boundary transitions = 131.
- Two single-member output groups: two times (six fold units + three fields +
  one commit) = 20.

Total control work is **1093**; 1092 fails with typed `PoolWorkLimit` for quanta
one, seven and 256. No expectation is extracted from a successful measurement.
The existing structural workspace is two four-slot records in each of two sort
buffers plus five output slots and two key slots: **23**; 22 is rejected before
sort allocation. Output contents and typed group order agree for all quanta.
These are Pool control/structural bounds, not whole-Run exact Ledger budgets.

The unchanged product failed the new executable regression with `69 != 1093`
(`run-EnegyG`, `focused-test-MYtHv8`, one test failed). The earlier compile-only
attempt was a fixture type error, not a reproduced product failure.

Cancellation barriers at control units 40, 600, 750, 900 and 1000 directly check
the pending cursor in validation, identity sort, duplicate detection, group
sort and group boundaries. Cleanup before stop is rejected. After confirmed
stop, work is retained, cleanup releases private state once and the input lives.

## Ordinary public retained path

[The installed Host test](../../adapters/host-node/public-pool-key-retention.test.mjs)
uses an ordinary Program with typed Vector values:

```text
Values -> exported Relation
  -> to_vectors -> pool_vectors -> vectors
  -> producer Named Result and two consumer tasks
```

The Carrier chain stays in one fused task. All three public Result names are
read explicitly and compared with authored ordered rows. A real retained-file
representation is observed. Same-request resubmission produces no new Compute
or dispatch.

After `to_vectors` completes, the first 256-work Pool child quantum is suspended
by the existing awaited Host hook. The matching core fixture asserts
`ValidateGroups` with a pending 513-code-unit key at this exact boundary.
Public cancellation persists the request without confirming physical stop or
publishing any result. Releasing the barrier confirms stop; all Results remain
unavailable, snapshot files are reclaimed and no further Compute/dispatch is
reported. Files present at the barrier do not change before stop confirmation.
The core fixture supplies the borrowed-root ownership evidence; empty snapshot
directories are not a complete holder/reservation census.

The initial public diagnostic mistakenly addressed a split task; it failed
because the ordinary provider correctly retained the fused task. Its trace
located the child transition, without changing Program splitting or production
selection. That failed attempt is not counted as cancellation acceptance.

## Executed focused checks

Checks ran on the source candidate descended from
`86959b5d7f7c5c250afa75523637c11ee6c40fb7`, before its final commit. Evidence
retains that parent SHA and working-tree scope rather than claiming clean-HEAD
distribution acceptance.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/local_veca/pool_text_comparison_wbtest.mbt \
  src/local_veca/pool_wbtest.mbt src/value_admission/key_order_wbtest.mbt
node scripts/local-checks.mjs test moon -- --target js \
  src/query_integration/local_carrier_vectors_wbtest.mbt --filter '*pool*'
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-pool-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

- Core: 23/23 (`run-DPfSks`, `focused-test-kaDGVQ`).
- Registered/Host Pool callers: 9/9 (`run-CzKvPE`, `focused-test-UGhEEM`).
- Public Host and gate/index mutations: 206/206, comprising 1 + 201 + 4
  (`run-i9h1La`, `focused-test-DcMmOP`).
- Only `local-node` runtime was rebuilt from the integrated MoonBit sources;
  its existing freshness check passed. No runtime bundle is tracked.
- Resource audit, changed MoonBit formatting and `git diff --check` passed.

The gate rejects removal of any long-key role, the public fixture or its actual
installation-suite import. The existing shared profile is not blanket evidence
of every operator's internal comparison scanning.

Not executed here: Wasm/native, full Core, packed/HTTP, proof campaigns,
performance/stop-latency measurement, new Store fault campaigns or D's restored
Model cancellation acceptance. Relation composite-identity encoding, nearest
and ranking comparisons remain separate scanning work. This unit does not
claim complete Local retention or establish merge readiness from Draft CI.
