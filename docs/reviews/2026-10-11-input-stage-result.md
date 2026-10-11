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

## Public acceptance status

The dedicated profile is:

```sh
node scripts/test-packed-public-query.mjs --input-stage-result-only
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

Corrected integrated-source packed acceptance is pending the shared heavy slot.
Package digests, successful transport/restart results and the final termination
receipt must be added before this unit is handed over as complete.

Hosted CI, Preview, full Core/proof campaigns and all other empty-Stage Carrier
shapes have not been verified by this unit. Graph four-operator completion is
unchanged. Issue #1195 follows this unit's public acceptance and PR handoff;
issue #640 follows #1195.
