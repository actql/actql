# Current provider cleanup completion and construction census

Adopted main: `cf0784dcb9459a92fca77708d8e3f1f526dd757b`.
Clean Native execution: `af46c827ad2c23f4eb1986b5e42ccf8f40b1df6b`.
Publication adds only this review and its evidence archive. The original Native
receipt retains its execution revision; it is not rewritten as the publication
revision or as an Actions original.

## Failure and reviewed source correspondence

The existing provider-construction and chain-source Node selection on clean
main failed: **7 passed / 8 failed**. The active recipe did not recognize the
already integrated cleanup adapters. The selected-provider digest changed from
`30bd9c86dadd9ce26940046216ebfa640453ab0f34f2224068e7c1ea6b87e07d`
to `40dbff3cc79f6d83d2dffd2f2d41bf514738bcaa5c1a728b810fcf6d343b892f`.

The new correspondence requires the exact source changes from
`fe269370560b4a0466bb0ffed74c813a7f846d2c`:

- `a9edb078d801d547fbf19aae56c39c4233f32d00`: all eleven providers translate
  the lower cleanup transition Bool through the existing `cleanup_pending`
  witness into managed completion. False/error retain pending responsibility.
- `eb3a7a78a7426a9be397b62545e76984a25aba43`: the existing scratch-eligibility
  helper additionally admits detached Values and UNNEST completions. The exact
  full helper body is required; arbitrary family admission is rejected.

Removing only those exact reviewed bodies must reconstruct the independently
recorded historical bytes. The selected factory, parent state and capacity
function remain byte-identical to that baseline. The other ten entire provider
sources reconstruct their actual baseline blobs. This is source correspondence,
not an old-source admission path. Historical recipe/source refusal tests remain.
Refreshing hashes alone cannot admit a changed completion witness, swallowed
cleanup error, missing eligibility or unreviewed family.

The active recipe digest is
`698c9e6e46ceac867727afed69c16a5eafd6b9dbeffc779a329effe38d258a6c`.
The original scientific census and recipe are preserved. The conditional
construction component remains **2344 bytes**; no capacity allowance was raised.
Set/Nest `Result.map` callbacks evaluated during cleanup, temporary execution
allocations and accepted payloads remain outside that construction component.

## Executed checks

| Check | Source state | Result |
| --- | --- | --- |
| Provider construction + chain source Node tests | Working implementation on adopted main | 23/23 |
| Existing chain lifetime JS file | Same working implementation | 8/8 |
| Existing parent-control Native observer | Clean `af46c827ad2c23f4eb1986b5e42ccf8f40b1df6b` | 1/1, final consumer accepted |
| Existing chain lifetime Native file | Same clean revision, after observer restoration | 8/8 |

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  proofs/relation-pipeline/provider-construction.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/chain-source.test.mjs

node scripts/local-checks.mjs test moon --timeout-seconds 240 -- \
  --target js --jobs 2 \
  src/connectors/local/relation_chain_lifetime_wbtest.mbt --deny-warn

# Sequential existing entries under one shared heavy guard, 900s budget:
node proofs/relation-pipeline/capacity/parent-control/run.mjs
moon test --target native --jobs 2 \
  src/connectors/local/relation_chain_lifetime_wbtest.mbt --deny-warn
```

MoonBit uses the checked-in `0.10.12+1634b282e` pin. Lean uses
`leanprover/lean4:v4.30.0-rc1`. The archive includes the exact bounded guard
invocation. Its receipt is `run-hrj7Tx`: complete output, exit 0, locks released;
Native observer took 50.25s and the subsequent lifetime consumer took 25.71s.
The Native lifetime receipt is `focused-test-ypIan0` (clean source). The observer
receipt is `focused-test-0Wp8pB` (explicit source-bound test overlay).
The read-only publication consumer `run-CZxwme` also accepted the archived
execution against the unchanged current input snapshot and checked the published
archive digests. It inferred no new execution and kept reuse authorization false.

Before the passing working-diff selection, an intermediate run had 15/22 pass;
it exposed the ten other stale provider pins and an incorrectly named extraction
target in the new test. Both were corrected. A sandbox process-group inspection
refusal and a missing-Moon executable attempt ran no tests; neither is counted
as a product or performance failure. Their raw logs are retained separately.

## Actual Native findings and limits

The unchanged observer verifies seven phases through parent cancel, stopped
poll, cleanup false/error/retry, retained completed Array and nested preparation
cursor, then cleared ownership. It binds actual capture identities to current
source/ABI roles, restores original bytes, audits the final consumer and rejects
**28 receipt substitutions**. These refusals are not 28 physical mutations.
The existing lifetime file independently checks Values/UNNEST output generation,
order, exact rows, pending-child custody, retry, no extra Compute and no next child
after cancellation. Its expectations were not regenerated from product output.

The actual eleven-candidate point has 1184 indexed requested bytes. Twenty
dynamic scalar callbacks contribute another 320 requested bytes from audited
allocation sites in both the archived object and executed binary: **1504 bytes
at this point**. Scalar payload bytes were not measured from GC descriptors.
The object digest is
`f64913a1db1f4950739bae7ac3d9e3316de0e07c936f696ed7e91a89f55b6c96`;
the observer executable digest is
`a1fc31f9fb47b009d06b99e49287aad921112f7affb66039adc95e352ddb9ff9`.

Seven existing conditional Lean propositions and their expected applications
and axiom audit pass. The two-child retained-core conditional envelope is 808
bytes. Neither 808 nor 2344 proves a complete parent or pipeline physical bound.
On darwin-arm64 the primitive-Ref allocation decoder remains unresolved; its
payload ceiling is an ABI premise, not newly measured evidence.

The observed startup lower bound is **600 bytes**, exceeding the independent
`2 * 256 = 512` handle component in `bounded_relation_chain_capacity`.
This is a retained counterexample to treating that component as a physical
upper bound, not proof that the total reservation is insufficient: base/child
charges and the separate 512 preparation allowance still need allocation-union
correspondence. The next product-boundary decision belongs at that function and
its allocation/custody ownership, without substituting 600 as a guessed bound.
Accepted payloads, borrowed referents, temporary/observer allocations, allocator
rounding and whole-owner retirement are explicitly unaccounted here. Source
clearance does not prove physical destruction or Ledger generation retirement.

## Published evidence and remaining goal

[Text evidence archive](evidence/2026-10-08-chain-cleanup-census-af46c827a.json.gz)
contains unchanged report/log/guard bytes, model receipt, actual disassembly,
historical and current provider sources, and failure/pass chronology.
Uncompressed JSON: 1,935,881 bytes, SHA-256
`b5aba2fea4778601a00b26cea91a9d5d89278038643beef58fe4643e924c0d70`.
Gzip: 530,591 bytes, SHA-256
`8412ede8bd4674e3026addf579f9700b661bbf07aabb008ef11a90b2ce109276`.
Original object/executable bytes remain in content-addressed local custody; the
published text archive cannot independently repeat their audit without them.

This closes current-source construction admission and finite Native custody
correspondence for the reviewed adapters. It changes no product, workflow,
selector, verification obligation or reuse authorization. Full hosted/three-target
coverage, complete physical bounds, successful main Actions originals,
cross-main qualification, ordinary-PR `mutations-js` reuse and authentication/
transfer-inclusive net CI savings remain unfinished. No Actions were started or
polled. Their existing resume procedure remains unchanged.
