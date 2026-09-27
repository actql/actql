# Local preparation owner consolidation

## Scope and baseline

Base: `87530f7185c26a3663ae0a6c0bf6f95dd8c33dd3` (main after PR #18).
Implementation: `d72d8a9353d69c3a5a5ee8709f7b654c5be52791`.

Main subsequently advanced to `02c279a39567febbc11fb75a463bd6fbe92fb284`
(Frontend PR #20). Integration retains its structural-AQL packed smoke and
this branch's removal of the extra runtime package. Main's grammar pins change
Plan identities independently of this refactor. Compatibility snapshots were
refreshed against the standalone compiler under those exact pins. Specifically,
the structural-text grammar and rules hashes changed the grammar manifest CID
from `sha256:a203bf073a9d3ad122fd6e8428e713617a3ce812d8171e3d684c250d70aa0c7a`
to `sha256:276726dc68f24e777b1421efc62b3f2518d9440530827b1f084f535e23d765ea`.
The fixed Values and Task Plan CIDs changed from
`sha256:5bb63ee040f2988dc694fc75b91bbab154053283588653a4f4bae0b4d1406dd4`
and `sha256:88c46b0d0a30df30c7bb7efbbd7d2452a6b8baf183aa5203040d8900f4397e47`
to the values in `local-values-plan.test.mjs`. That test now
compiles each fixture through both the consolidated owner and the separately
built standalone compiler under the same new Frontend pins and compares their
full Plan CIDs. The Template expectation also reads the pinned manifests.
The measurements below retain their original same-pin baseline and are not
comparisons across grammar pins.

This unit removes duplicate initial preparation and compilation in the
installed Local Values and acquired Task paths. It does not add execution
profiles, change algorithms, redesign the SDK, or optimize Effect processing.
Wire contracts, CID preimages, authorization and contract version 0.1 remain
unchanged. The standalone Run Host Core JavaScript API remains unchanged.

## Reconfirmed duplication and replacement guarantees

Previously, Local retained a checked Program in `connectors_builtin_node`,
then `local-values-plan.mjs` admitted the environment and prepared the same
document in the separately loaded `client_values_host_abi` runtime. Both
runtimes compiled it. Comparing Template and Plan CIDs checked agreement
between the independently reconstructed owners before issuing Run evidence.

The replacement is not removal of those comparisons in isolation:

- The preparation installation privately owns its returned handles and rejects
  another installation's or a copied handle before Local planning.
- Values and Task compilations retain the exact prepared MoonBit owner.
  `ClientCompiledRun` requires that owner and retains the compilation,
  prepared/authorization evidence and admitted Run together.
- Internal ABI wrappers transfer these typed values through the existing
  publication control's private handle maps. No public raw-handle import or
  cross-runtime WeakMap bypass is introduced.
- Run Definition issuance and Invocation composition use that same owner.
  Durable restoration still parses and checks the retained definition; it
  does not authorize recomputation of an uncertain prior dispatch.
- Both environment ABIs use one bounded admission helper. ABI-specific profile
  guards remain outside that helper, including restricted SGA rejection.
- Local no longer depends on the separately packaged Run Host Core runtime.
  Its standalone entry and private handle ownership remain supported.

See [Local adapter](../../adapters/host-node/local-values-plan.mjs),
[common owner](../../src/run_publication_host/client_compiled_run.mbt), and
[environment admission](../../src/run_publication_host/client_environment.mbt).

## Acceptance evidence

| Boundary | Evidence |
| --- | --- |
| Initial Values and real-input Task prepare/compile | Each is called once in `local-values-plan.test.mjs`; the separate profiler probe also detects the former portable runtime calls |
| Exact owner custody | Different preparation installation, copied handle, foreign control, and equal-content foreign prepared owner are rejected |
| Identity | Template and Run Definition preimages are assembled independently from fixture context and pinned manifests; Plan CIDs match both fixed snapshots and the test-only standalone compiler under identical Frontend pins |
| Existing independent expectations | Standalone Core tests retain the independent logical Result Plan and output-contract vectors; shared compilation tests retain authored identity material |
| Restoration | A retained Run Definition preserves identity; a rehashed definition naming a foreign Plan is rejected |
| Product Values and acquisition | Standard Client bridge and packed Local exercise publication and Result reading, including real DuckDB input and downstream computation |
| Standalone and restricted profiles | Standalone Core, packed package smoke and dependency-free module-subset checks pass |

The complete Plan compatibility snapshots are baseline comparisons, not new
independent reference-compiler vectors. The test-only two-runtime comparison
isolates the owner consolidation from the grammar-pin update. This refactor
changes no Plan identity algorithm. Existing independent lower-level identity
expectations are retained; test output is not relabeled as an independent oracle.

## Local verification

Host and Client jobs ran at `fd0ffffc65b0db3e619b16abee51cff3e9f1185a`.
The later commit only adds identity assertions and probe metadata. The final
targeted test, lint and core jobs ran at
`12efdf612a2174dbd1c11ee2c9800313ee7d564b`; its source tree is identical to
`d72d8a9353d69c3a5a5ee8709f7b654c5be52791` (commit-message wrapping only).

- `node scripts/local-checks.mjs run host`: passed, including standalone
  Core 23/23 and packed Local assets. The first sandboxed attempt encountered
  an npm cache permission error; the authorized rerun passed in full.
- `node scripts/local-checks.mjs run client`: passed; Client 172/172,
  packed Node/browser smoke, Salesforce regression 192/192.
- `node scripts/local-checks.mjs run lint`: passed, including format, generated
  public interfaces and dependency-free standard-entry tests (62/62).
- `node scripts/local-checks.mjs run core --target js`: 6,745/6,745.
- The same core job with `--target wasm`: 6,742/6,742.
- The same core job with `--target native`: 6,803/6,803.
- During editing, `run_publication_host` passed 15/15 on each target, and
  Client bridge plus Local plan tests passed 26/26.
- Generated runtime bundles remain ignored build outputs. Reviewed generated
  ABI wrappers and `.mbti` interfaces were regenerated from source.
- `node scripts/local-checks.mjs run spec` passed with this result record and
  the package README update present, including links and generated contracts.

After merging Frontend main at `b5669a863e928a34d300b3bb9ba110d9eaa1809f`,
the ignored Local and standalone Core runtime packages were rebuilt from the
integrated sources. The test-only same-pin compiler comparison passed for both
Values and acquired Tasks. The Host, lint, spec, and core JS jobs passed; core
JS reported 6,769/6,769. The Client job passed its Node tests (172/172),
packed Node/browser smoke, packed Checkpoint acceptance, native Client mTLS,
and Salesforce regression (192/192). An earlier Client attempt was interrupted
while its native build waited on a MoonBit lock; the later complete run passed.
Linux CI on the final pushed SHA remains a separate check.

Linux CI on the PR's final pushed SHA is separate evidence and must be checked
on the PR. This local record does not assert that CI or a main merge occurred.

## Small preparation measurement

Probe: `node scripts/measure-local-preparation.mjs [checkout-root]`.
Five warmups, then seven samples per fixture; median wall time, Node 22.23.2
on macOS arm64. Build and provider I/O are excluded. Actual call counts use a
separate V8 coverage pass, not instrumentation during timing.

The pre-change checkout was `3a19a36446bff5d6c5359c0a28803709ebf7dbab`.
Its Git tree equals the main baseline tree
`c00a5aa29eaa1008c161d5821c5ab1850fcb36f2`.
The post-change checkout was the implementation SHA above.

| Fixture | Before median | After median | Initial prepare / compile |
| --- | --- | --- | --- |
| Values | 21.17 ms | 10.74 ms | 2 / 2 to 1 / 1 |
| Acquired Task plan | 34.62 ms | 16.54 ms | 2 / 2 to 1 / 1 |

Both probes reported load averages 31.64 / 123.34 / 95.33 after the sequential
core jobs. These small warm samples are diagnostic, not an isolated benchmark
or a promised speedup. The structural call reduction is the acceptance gate.
No 27-case performance rerun or new performance target is introduced.
