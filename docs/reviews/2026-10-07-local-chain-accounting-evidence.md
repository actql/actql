# Independent retained chain accounting boundaries

Verified source: `7f4abd75282728793f5b0a98969de23b4db60db3`.
Adopted main: `8285dce99e7232e56044e02d218eb4deed574e35`.
The input-readiness and output-reclamation parents are now on main. This
fixture-only change does not alter execution, limits, public APIs or identity.

## Independent expectations

The old fixtures omitted charged completion-port preparation, or the two fixed
chain preparation handles. They also failed on the unchanged parent of the
input-readiness change. This is not a reduction of production charges or a
replacement expectation copied from a successful execution meter.

For the fixed ASCII identifiers and field names in these fixtures, preparation
costs `3 * identifier.length + sum(field.length) + field.count + 4`: two scalar
identifier scans, one UTF-16 comparison, three identifier phase boundaries,
one end per field, and final completion. This is deliberately not a general
Unicode formula. The fixed IDs follow the lowerer's operation naming rules:
`where_1`, not `filter_1`, and `window_group_2`, not `group_2`.

| Fixture | Algorithm work | Port preparation | Handoffs | Exact work |
| --- | --- | --- | --- | --- |
| Two-row Values | 21 | 37 | 0 | 58 |
| Values / true filter / select | 20 + 31 + 19 | 31 + 28 + 31 | 2 | 162 |
| Keyed count / filter / select | 54 + 37 + 15 | 30 + 30 + 31 | 2 | 199 |
| Values / window / window group | 30 + 64 + 213 | 33 + 57 + 74 | 2 | 473 |

Each fixture retains its algorithm phase breakdown. The source-free fixture
also executes each selected checked child against independently supplied
expectations, using exact operation binding for the preceding completed output.
Its finite poll ceiling now includes the newly charged preparation steps.
Quanta 1, 7 and 256 must give the same whole-chain work and independent rows.
An exact ceiling completes; one-short must retain the typed work-limit cause,
never an unrelated failure. Existing workspace and cleanup checks remain.

The keyed count's two captured rows give COUNT scratch 12 entries; its later
filter peaks at 14: metadata 6, input roots 2, snapshot 2, output cells 2 and
checked cells 2. Exact 14 succeeds, while 13 and 12 fail with the workspace
cause. Source-free workspace remains 9/8 and window-group workspace 37/36.

Chain execution capacity retains child outputs, one reusable maximum child
scratch envelope, and 256 bytes per child handle. The existing production
capacity owner additionally reserves two 256-byte preparation handles for
input selection and common read preparation. Both stale capacity assertions
now include these handles. The implementation already did so; no capacity
ceiling or reservation behavior changes here.

## Executed verification

All commands below ran on the clean verified source above, on JS with the
pinned toolchain, through the existing nonzero-test and timeout wrappers.
The subsequent record commit adds documentation and formatter-only changes to
two fixture files; it does not relabel those runs as execution at a later SHA.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/query_integration/local_managed_unary_wbtest.mbt \
  src/query_integration/local_retained_values_chain_wbtest.mbt \
  src/query_integration/local_window_group_chain_resource_wbtest.mbt \
  --filter '*exact*'
```

Passed 8/8: `run-fHNh5N`, `focused-test-vuCE4T`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/query_integration/local_managed_values_wbtest.mbt \
  src/query_integration/relation_chain_scratch_capacity_wbtest.mbt
```

Passed 24/24: `run-kG6Yl0`, `focused-test-qS1jFz`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/query_integration/local_managed_unary_wbtest.mbt \
  src/query_integration/local_window_group_chain_resource_wbtest.mbt \
  --filter '*chain*'
```

Passed 8/8: `run-jF6Zw6`, `focused-test-LnVr6W`. Selections overlap; these
counts are not a claim of 40 distinct cases. They include the captured chain's
ordered two-consumer outputs, capacity and existing post-progress cancellation.
The window cancellation occurs after the first two children, during the group
child's preparation; no new claim of cancellation inside group comparison is
made. Receipts remain under `_build/local-checks/attempts` and
`_build/focused-evidence`.

## Failed preparation attempts and limits of evidence

The provisional dirty-source attempt `run-R48Et7` passed 31/33; the two failures
exposed incorrect assumed lowerer IDs in the source-free and window fixtures.
`run-ORWxIG` failed its one selected source-free child check. Inspection of the
lowerer, not adoption of measured totals, corrected those assumptions. The
subsequent five-file dirty-source attempt `run-gxb1x3` timed out after 120
seconds with exit 124 and no test counts. It is not a pass. The clean focused
commands above subsequently completed without increasing the timeout.

No runtime bundle or distribution artifact was regenerated: the PR changes
tests and records only relative to adopted main. No new-SHA packed, HTTPS,
Wasm/Native, full Core, proof, performance or CI success is claimed. The
[input-readiness public Host evidence](2026-10-07-local-input-readiness.md)
remains tied to its original source SHA and is not relabeled as this SHA.

This resolves the documented stale chain expectations, including the two
fixtures discussed in [accounting issue #498](https://github.com/actql/actql/issues/498).
It does not close the whole retained Local goal. Installed availability
callbacks, other scratch walks and Native allocation/reclamation correspondence
remain separate implementation or acceptance boundaries.
