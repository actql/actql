# Common INFER connection readiness

## Inspected source

Only committed objects on `feat/common-infer-execution` were inspected:

| Full SHA | Implemented boundary |
| --- | --- |
| `6e6dfe400727a13e3247c748054f0c1905bfea63` | Shared object construction and nullable property lowering/evaluation |
| `a6abc1250286119dd05f2685ac796e35c903370e` | Typed ModelTask and execution-contract readers |
| `34dbe6ee648d5a34d4acdc03fc19fcdcaba453db` | Standalone checked inference input expressions and candidate-key bindings |

These are inspection references, not adopted runtime handoff SHAs. None was
merged or cherry-picked into B's preparation branch. A's uncommitted input
execution work was not used as evidence, modified, built or tested.

The existing [Frontend handoff](2026-10-01-infer-keep-handoff.md) and
[packed preparation](2026-10-01-infer-packed-preparation.md) remain the
acceptance baseline. Frontend #112 is complete; packed inference is not run.

## Committed call contracts and acceptance gaps

| Boundary | Committed operation or type | Match to prepared acceptance | Still required |
| --- | --- | --- | --- |
| ModelTask admission | `check_environment.check_model_tasks(WireEnvironment, ModelTaskLimits) -> Result[ModelTasks, ModelTaskIssue]`; `resolve_model_task(ModelTasks, String)` | Exact `model-task:risk-score.v1`; non-null closed input object with nullable `text`; non-null closed success object with non-null `risk` and nullable `reason` | Real Host registration/configuration, admitted dependency bodies, current authority and finite execution limits |
| Execution contract | `read_model_execution_contract(ModelTaskContract, Bytes, String, Limits, Int)` | Exact task identity and finite attempt, cost, duration, wire and token ceilings | Retry-classification/backoff/prompt/data-handling dependencies and physical adapter planning; this reader does not authorize calls |
| Typed operation | `infer_typing.check(Cursor, Carrier, KeySet?, ModelTasks, Declarations?, Limits) -> Result[CheckedInfer, Issue]` | Existing `contract`, `key`, `input` body; complete Relation schema and exact owner-bound key witness | Invocation through ordinary Program/pipeline checking, capacity admission and executable lowering |
| Input expressions | `input_binding_at(CheckedInfer, Int) -> InputBinding?`; binding retains `role`, source Cursor and `TypedExpression` | `text = text` preserves nullable input; no SQL-string interpolation | Evaluate the admitted mapping against the retained input and bind actual requests/slots; the uncommitted connection is not yet adopted |
| Item identity | `key_witness`, `key_at`, `key_count` on `CheckedInfer` | Explicit whole non-null scalar candidate tuple `id`; authored tuple order retained | Fulfill pending physical key validation before any model send, including duplicate acquired keys |
| Output shape | `output_schema(CheckedInfer)` produces key fields plus `outcome` and nullable `value` | Frontend already builds `assessment.input_key/outcome/value` through ordinary object projection | Produced-key evidence for KEEP's one-to-one join, actual fixed outcomes and success refinement; no new infer wire fields |
| Objects/properties | Shared `ExpressionBody.Object` and `ExpressionBody.Property` | Nullable receiver returns NULL; nullable `reason` survives; missing fields fail | Combined inference output → KEEP/AS → nested filter → formal Result proof and execution |
| Program and Host | Committed `pipeline_typing/check.mbt` still falls through to `UnsupportedOperation("infer")` | The acceptance application uses normal `aql`, Run owner and Named Result | Common barrier dispatch, capture, replay and existing Host/publication connection |

`CheckedInfer` and `ModelTaskContract` are opaque owners. A same-shaped schema,
task member or key from another owner cannot substitute for them. Admission
and classification compatibility do not constitute model-egress permission.

The prepared fixture's `candidate_keys` entry is a requirement on the installed
SourceView/check environment, not permission to synthesize a witness. A must
identify the existing key issuer and runtime validation connection. The
source-free Values golden fixture remains a lowering expectation: unique
literal rows alone do not prove a candidate key. Do not change that fixture
into an allegedly executable proof or invent a key from its row values.

A's typed checker fixture uses matching input/output schemas and task selector,
but some dependency CIDs are placeholders in standalone admission tests. They
must not be copied into an executable Host configuration as admitted prompt,
data-handling, retry or backoff evidence.

## Required adoptable handoff from A

1. A complete published adoption SHA and its required dependency order. State
   whether it includes the normal Program checker, executable inference owner,
   shared object/property evaluation and public Host connection. Preserve any
   remaining limitations explicitly.
2. A minimal real Host startup and ModelTask registration example using the
   installed public packages. Include the exact task/execution/dependency
   bodies, deterministic physical model adapter, current authorization, finite
   limits, SourceView alias/schema/key setup and generation binding. Identify
   the actual public operations; do not provide a fixture-only owner as the
   product entry point.
3. Supported input/output/result modes, key and request preflight, capacity,
   stop/cleanup, outcome publication and replay boundaries. Identify the
   owner responsible for each retained input, attempt, response and Result.
4. Capture/replay implementation and fixed-source validation status. Explain
   how an admitted request reaches physical dispatch, how each actual outcome
   is sealed under `actql-model-slot-capture/0.1`, and how re-read/attach/same
   request/restart preserve captured observations without provider calls.
   Unimplemented boundaries must remain explicitly unfinished.

B's prepared standalone test setup interface is `openInferTestHost({mode,
fixture})`, returning `options`, `prepareCase(rows)`, `observe()` and `close()`.
This is an acceptance-controller interface, not a new product API. Its
observations must be real cumulative `acceptedRuns`, `sourceIo`,
`modelDispatches` and `capturedSlots`; the setup cannot inject finished Result
rows or reset counts. B connects this setup after A's public handoff.

## First installed acceptance, then full KEEP/AS

After adopting the complete handoff, first install one physical source row:

```json
{"id":"a","text":"urgent","secret":"private-a"}
```

Publish `tickets` through the real Host configuration with its existing
complete schema and validated candidate key, then use the same application
with Local and HTTP connection options:

```js
const client = await connect(options);
const execution = await client.aql(
  'FROM tickets |> INFER `model-task:risk-score.v1` ' +
  'ITEM KEY (id) INPUT (text = text) AS assessment',
  {format: 'aql-text', requestId: 'infer-first-path'},
);
const state = await execution.wait();
const result = execution.result('answer');
const description = await result.describe();
const rows = await result.all();
```

The independent expected row is:

```json
[{"assessment":{"input_key":{"id":"a"},"outcome":"ok","value":{"risk":"high","reason":null}}}]
```

Require succeeded Run/publication, the complete `omitted` column contract in
the prepared fixture, one real model dispatch and one retained slot capture.
One row needs no additional ordering declaration. Missing setup or unsupported
execution is a failure, not successful acceptance or an automatic skip.

Then run the existing prepared Local/HTTP application for KEEP/AS, failed
typed NULL, nullable members, empty input, nested properties, column order,
scope/key refusals and no extra execution on re-read/attach/same request.
Preserve its explicit ordering and authored expected values. Capture/replay
provenance and mutation refusal require A's common-owner evidence as well as
the public application; counters alone do not prove those contracts.

## Verification of this readiness note

This is a committed-source inspection. No A changes were adopted, no runtime
bundle was generated and no full gate was rerun. A's documented test results
were read as partial evidence, not independently rerun or attributed to B's
packed acceptance. Existing `execution_status: "not_run"` remains unchanged.
