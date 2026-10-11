# Input-only Relation Stage Result execution

## Completion unit

Issue #1350's independent structured Program remains unchanged: a Values
producer exports `rows`, and a second Stage with `steps: []` returns its
Relation input. The public expectation is `answer = [{"A":0}]`, with column
`A` of nonnullable Number type. No projection or artificial operation is
inserted to make this Program executable.

The accepted empty-task profile has exactly one Relation input and selects
that exact input as its output. Empty Graph/Events/Vectors tasks and other
empty-task input shapes are not included. They retain the existing rejection
path rather than acquiring a synchronous fallback.

## Existing Owner connections

| Boundary | Connection |
| --- | --- |
| Checked DAG | Preserve `Input(0)` as the actual task output target. |
| AoA emission/schema | Emit the authored input port `source`, no steps, and its checked schema. Physical material retains the distinct `input_0` coordinate. |
| Run opening | Admit only the exact single-Relation-input empty task; preserve ordered input completeness and all source/edge checks. |
| Local provider | Reuse the existing bounded binding-row copy cursor, value admission, cumulative charging and cancellation control. |
| Completion | Validate exact raw or managed receiving-port proof before accepting the input-target material. Omitted or empty proof is rejected. |
| Managed re-admission | The private bridge constructor preserves the exact completed generation and its original binding identities; it does not fabricate raw receiving proof or recheck upstream liveness. |
| Result root | Use the actual checked target/schema, preserving the existing Result ordering and publication Owner. |
| Retention/recovery | Use the existing managed output, Store, publication, cleanup and retained-Result restart paths. |

No new Scheduler, ledger, completion Owner, wire contract, identity domain or
capacity limit is introduced. The provider construction review normalizes only
the two exact input-only branches back to the previously reviewed source;
its mutations still detect widened input acceptance or a changed coordinate.

## Fixed counterexamples

- `run-B8dNId`: the unchanged Issue Program failed task emission with
  `MissingOutput` before the initial connection.
- `run-DXqjgQ`: ordinary preparation followed by Run opening failed with typed
  `Run(UnsupportedGraph)`, because the existing DAG Owner required a step.
- `run-acVrAr`: the same two compiler/Run-opening cases passed after the exact
  input-target admission correction.
- `run-Br8yRh`: the standard Host progressed past Run opening but failed with
  `ManagedCompletion(ForeignInputs)` at finalization. Managed input proof was
  being checked after raw-input-only target admission.
- `run-uEqCoa`: that standard Host case completed both tasks after checking the
  existing managed proof first. This was a source-backed diagnostic, not packed
  public acceptance.
- `run-39KcXa`: ordinary public execution reached publication, then failed with
  `CapturedRunPublicationFailed` / `DurableResultPayloadFailed` /
  `MoonBitHostFailure(InvalidCommand)` at `beginManagedResultImport`.
  The publication bridge was re-admitting input-target output without its
  already verified managed completion provenance. Commit
  `e052efcdc1cdca83e185441651e7185f68bca016` connects both existing managed
  bridges to a private constructor that retains that provenance. The public
  raw completion entry still rejects omitted/empty receiving proof.

Two acceptance-fixture corrections are distinct from product counterexamples:

- The shared Values oracle preserves `[2,0,2]`, not a field-sorted `[0,2,2]`.
  The existing `REL.values` occurrence-order rule and Named Result ordering
  precedence require inherited total order before canonical completion.
  `client_input_result_wbtest.mbt` checks `Inherited` with zero sort terms;
  `input-stage-result.test.mjs` independently rejects the sorted alternative.
- `run-vA6kDY` passed normal/restart acceptance but failed the Store-fault tail:
  the fixture omitted `retainedRelationOutput: true`, so no lease was allocated
  and no failure was injected. `run-IXG6mj` confirms that absence. The corrected
  fixture enables the real row-only Store and targets `task-1`, not the managed
  Carrier descendant's `relation-task-1`. It verifies the lease and injected
  failure before asserting the public unknown/nonpublication state.

The failed receipts are preserved separately; they are not relabeled as success.

## Executed focused checks

Source commit: `00e37399516435b5f32edfa757392305075f8fe7`.

The selected files were:

```text
src/execution_relation/input_result_wbtest.mbt
src/execution_relation/managed_completion_wbtest.mbt
src/run_publication_host/client_input_result_wbtest.mbt
```

`run-fmKLYb` used the existing bounded local guard and
`runFocusedTests("moon", ["--target", target, ...files])`, sequentially:

- JS: 14/14 passed (`focused-test-eYRFzD`).
- Wasm: 14/14 passed (`focused-test-7jpNgO`).
- Native: no successful execution summary. The invocation reached its 420-second
  aggregate deadline after JS/Wasm; Native received SIGTERM. The original
  receipt records closed output streams, exit 124 and `locksReleased: true`.
  This is incomplete Native verification, not a product-failure classification.

The earlier source `091481a201cb0e150ed1b699745fbf29e84b71d2` had narrower
JS 13/13, Wasm 4/4 and Native 4/4 success in `run-O6BEnO`. Those results do not
establish success of the later managed-proof correction on Native.

Main `a5526fda6aebee6de7a775ae5268e4036b4d6b46` was normally merged at
`f2b99f56584afac88a60407688549ff13ed4603b`. No edited custody implementation or
selected regression file changed in that integration. The shared public-profile
test merged automatically with main's Frontend additions.

Later focused checks were retained separately:

| Receipt | Scope | Result and source correspondence |
| --- | --- | --- |
| `run-mcaVx1` | JS: `input_result_wbtest.mbt`, `managed_producer_bridge_wbtest.mbt`, `table_input_export_wbtest.mbt` | 17/17; working-copy implementation subsequently committed unchanged in `e052efc`. |
| `run-OpF8hD` | Source-backed public SDK input-only Result | 1/1 against the regenerated runtime; same implementation as `e052efc`. |
| `run-LZZLWl` | JS: `client_input_result_wbtest.mbt` | 3/3; test bytes subsequently committed unchanged in `463e329`. |
| `run-7PZoig` | Source-backed Local/HTTPS real-Store seal loss, cleanup retry and no re-Compute | 2/2; corrected fault fixture subsequently committed in `f3da343`. |
| `run-ZS3k0I` | Independent Program, profile and transport harness fixtures | 46/46; working-copy fixture changes subsequently committed in `f3da343`. |

Each receipt records actual command exit, complete output and lock release.
These working-copy diagnostics are not described as clean-HEAD packed runs.
The commands used the existing local guard/nonzero-test wrappers, pinned
MoonBit toolchain and Node 24.21.0 on macOS arm64; no all-Core gate was added.

At clean `e052efcdc1cdca83e185441651e7185f68bca016`, `run-huwrBG` passed all
26 provider-construction checks. The retirement fixture was 50/51: its Native
overlay helper compilation rejects `let` in the unchanged
`src/query_integration/python_local_source_publication_wbtest.mbt`.
The same helper rejection was checked against the adopted main's file.
This is a disclosed baseline limitation, not a successful proof campaign or
an input-only runtime failure; no proof parser or expectation was weakened.

## Public acceptance status

The dedicated profile is:

```sh
node scripts/test-packed-public-query.mjs --input-stage-result-only --keep-artifacts
```

It builds the formal five-package cohort, installs outside the repository and
checks the unchanged Issue Program, empty input, and two independent consumers
through Local and HTTPS. It then invokes the existing fresh-process retained
Result reader and the existing real-Store failure/cleanup harness for the
input-only task. Fixed expected rows/schema and Compute observations are authored
independently in `scripts/fixtures/input-stage-result.mjs`.

The first packed attempt, `run-N2qZLi` at
`cfd09e11f148c4bc358f51354ac548810468e016`, built/installed the cohort but ended
with failed, unpublished Runs on both transports. Its evidence index is
`public-query-evidence-9dJSxv`; both workers terminated with zero live children,
and temporary installations were removed. It is not successful acceptance.

## Completed public acceptance

Clean verified source: `f3da34393cc0ec19d33c3e506138bea578854b98`.
The subsequent report/PR commit changes documentation only; its source and
test payload is not a different runtime acceptance cohort.

`run-MynwZY` ran the command above through `runLocalCheck`, with
`heavy: true`, a 300-second aggregate budget and a five-second TERM grace.
It ended at `2026-10-11T02:26:05.533Z`, exit 0, with `complete`,
`outputComplete`, `callerOutputComplete` and `locksReleased` all true.
The actual worktree/shared-heavy lock paths were also checked absent.

The packed evidence index is `public-query-evidence-GIdk7r`. It records the
same clean source before/after normal prepack, an external private install,
tarball digests, commands and their complete output. There is no adapter
overlay, ignored producer prepack or substituted source identity.

- Local and HTTPS each pass all three unchanged authored Program fixtures:
  Issue #1350, empty input and a shared producer with two input-only consumers.
  Independent rows, column type/nullability/order and duplicate occurrences
  are compared without sorting the public results.
- The explicit retained-Relation Host profile creates a real `task-1` Store
  lease. After ordinary close, every observed lease has zero reserved bytes
  and no pending cleanup. This is not memory-only Result publication.
- Fresh Local/HTTPS processes reopen the original retained roots and read the
  independently saved first/last boundary Results. Attach, identical submission
  and lookup preserve the original Run, with zero additional physical dispatch
  or Compute-advance observations.
- The real-Store fault tail passes 2/2: seal acknowledgement loss leaves Results
  unpublished and physical-stop unknown while cleanup is pending. Reconcile,
  identical submission, failed close and cleanup retry do not re-enter Compute;
  after retry, all reservation/cleanup state is cleared.
- The two initial workers (PIDs 38772/38773) and two restart workers
  (39414/39415) all record terminal exit 0, with `liveChildren: 0` in both
  process reports. Each transport inventory is exactly 3/3; each restart root
  inventory is exactly 1/1. Both inventories retain their independent digests.
- The harness's existing preflight is 50/50. Its repository-external README
  quickstart and public check boundaries also pass.

### Formal package cohort

All tarballs were normally packed from the verified source above. These are
development acceptance artifacts, not npm publication or release approval.

| Package tarball | SHA-256 |
| --- | --- |
| `actql-client-wire-0.0.0-development.tgz` | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| `actql-sdk-0.0.0-development.tgz` | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| `actql-run-host-core-0.0.0-development.tgz` | `26700a609149d95c2e0d6090e34745dd2c5b76149d437e09227e3c29e91387a8` |
| `actql-local-node-0.0.0-development.tgz` | `bdbe8d4de4cd91e501a077e1de8f2e15b5ea3944d1190352866b0d57daedd6b7` |
| `actql-node-0.0.0-development.tgz` | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Local guard receipts are retained under `_build/local-checks/attempts/<id>`;
focused receipts under `_build/focused-evidence`. The packed index, original
Host databases, publication objects, failure custody, tarballs and complete
transport/termination reports are retained locally by the evidence ID above.
They are not claimed as uploaded GitHub artifacts or CI execution.

## Unverified coverage and next unit

Hosted CI, Preview, full Core/proof campaigns and all other empty-Stage Carrier
shapes have not been verified by this unit. Graph four-operator completion is
unchanged. Issue #1195 follows this unit's public acceptance and PR handoff;
issue #640 follows #1195.
