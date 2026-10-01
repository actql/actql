# Common inference execution: implementation boundary

Branch: `feat/common-infer-execution`.
Base: `373764e0bd0c100451575cdb0b1a4e90f4e8ce43`.

This is an implementation record, not an inference completion declaration.
The independent acceptance Program and outcomes remain those in
[B's handoff](2026-10-01-infer-keep-handoff.md). No frontend evaluator,
alternative Run owner, model cache, or new wire version is introduced.

## Object and property execution

The existing checked expression forms now reach shared typed lowering and
Relation evaluation. Object members follow the contract's canonical UTF-16
field order. Property access carries a checked field ordinal; a nullable
receiver returns typed NULL without treating missing fields as NULL.

Ordered reference evidence includes every demanded child, with RFC 6901
escaping and UTF-8 pointer accounting. Closed-object construction uses the
existing immutable value builder and logical root owner. Temporary byte and
workspace reservations precede append; partial builders and roots remain
owned until completion or cleanup. Work is not refunded on cancellation.

Constructed objects and borrowed aggregate operands of object/property
expressions use the existing resumable measurement cursor. Reusing an exact
private root measurement avoids rescanning an immutable operand but retains
its full semantic work charge. This is not a claim that every existing
expression or scalar string operation has been changed.

The standard retained Host fixtures publish the KEEP-shaped object and its
filtered property projection, then read all three Named Results through the
real publication Store. Both consumers use the ordinary checked Relation
task path. Input rows and expectations are authored independently:

```json
[
  {"id":"a","note":"urgent","assessment":{
    "input_key":{"id":"a"},"outcome":"ok",
    "value":{"risk":"high","reason":null}}},
  {"id":"b","note":null,"assessment":{
    "input_key":{"id":"b"},"outcome":"failed:refusal","value":null}}
]
```

Filtering `assessment.outcome = 'ok'` and
`assessment.value.risk = 'high'` yields `[{"id":"a","risk":"high"}]`.
Values supplies already captured-shaped rows in these tests. It does not
stand in for inference dispatch, acquisition capture, or replay evidence.

Minimal common Host regression:

```sh
moon build --target js --release \
  src/connectors_builtin_node src/connectors/duckdb/conformance
node --test --test-name-pattern='retained object projection' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

## Remaining common inference implementation

| Boundary | Current limitation | Required implementation |
| --- | --- | --- |
| ModelTask admission | Typed task and execution-contract readers exist; Program preparation does not yet invoke them | Bind the admitted task to the checked infer operation and resolve prompt, retry, backoff and attachment dependencies before execution |
| Checked operation | The standalone typed infer owner exists; Program and pipeline preparation still refuse `infer` | Connect the typed owner, resolved capacities, produced-key evidence and success refinement with executable acquisition |
| Barrier execution | No shared checked model-call execution owner is installed | Preflight all keys, requests and adapter plans before dispatch; retain slot/attempt identity, reservations, stop observation and cleanup custody |
| Capture and replay | Existing publication code admits model evidence, but no inference owner produces it | Seal classified slot outcomes and real response/issuer evidence; replay captured observations without provider calls |
| Public Host | The current dispatch owner opens source-free or SourceView acquisition configurations | Connect the typed inference barrier to the existing Run admission, dispatch and publication owners; do not add a second Host state machine |

A owns the common ModelTask and infer implementation above. B retains parser,
source construction, independent Programs and packed Local/HTTP acceptance.
Any necessary Host adapter connection must use C's existing dispatch owner.
No dependency on an unspecified future Engine redesign is claimed here.

The independent Values fixture declares `key: id`, but Values itself does
not establish candidate-key evidence in the current checker. Its unique
literal rows are not a compiler-proven key. Acceptance input needs an
existing key proof, for example an `assert_rows.unique_by` producer or a
keyed input declaration. The expected model and Result values stay unchanged;
neither the frontend nor the infer owner may invent that proof from a name.

`run_publication/captured_run_issuance.mbt:captured_model_evidence` and
`run_publication/evidence_chain.mbt` already provide model evidence checks;
they must not be replaced by a new capture ledger. Existing
`actql.model_task/0.1` and `actql-model-slot-capture/0.1` bodies remain the
contract baseline. Checker acceptance will not be reported as executable
inference. The first runtime handoff can cover one real Host-dispatched row
while the remaining KEEP and replay acceptance is developed in parallel.
Capture and replay remain requirements for completing the inference unit.

There is not yet a SHA on this branch at which B's entire independent INFER
Program executes. Its successful packed acceptance remains pending. The
object/property tests are separate partial evidence, not a completed infer
unit. No external model service has been called.

## Local verification of the expression change

The pinned MoonBit toolchain and Node 22 were used. The final source passed:

- Object/property execution regressions on JS, Wasm and native: 8/8 each.
  These include nullable receivers, nested construction, independent exact
  and one-short work/live/value/workspace bounds, cancellation during
  construction and measurement, and a large borrowed object under coalesce.
- Complete `lowering_relation`, `execution_relation` and `query_program`
  JS tests: 1,366/1,366.
- Rebuilt standard retained Host object/property tests: 2/2. All three
  Named Results were read and compared; normal owner cleanup left no retained
  resources or execution reservations.
- Public interfaces matched JS/Wasm/native and the regenerated interface.
- `moon fmt --check` and `git diff --check` passed.

Before the final nested-context adjustment, the same three package suites
also passed 1,366/1,366 on Wasm and native. The final adjustment was rerun
through the eight affected execution regressions on all three targets,
the complete JS package suites, and both Host cases. This earlier broader
run is not reported as a full final-source Wasm/native suite.

The initial large-object fixture had a missing closed-contract flag and
used a small test parser limit; correcting fixture admission resolved those
test setup failures. Full lint/Core/DuckDB jobs, successful packed inference,
Linux CI and external provider acceptance have not been run for this unit.

## ModelTask contract admission

`check_environment/model_tasks.mbt` now checks every supplied ModelTask,
including unused declarations. It recomputes the task self-CID and both
embedded schema CIDs, reads checked non-null closed input/output objects,
validates generation and data handling, and rejects duplicate task selectors.
Nullable object members and absent optional limits are preserved. Lookups
retain the exact admitted environment; a same-CID foreign member is not an
interchangeable owner. Unknown classification never satisfies the task's
accepted-classification test. That test is compatibility, not Host authority.

`check_environment/model_execution.mbt` reads the registered
`actql-model-execution-contract/0.1` body. It checks canonical bytes, self-CID,
the exact admitted task reference and all six finite execution ceilings.
Retry-classification, backoff and media contract CIDs remain unresolved
dependencies. Reading this body does not authorize retry, media access or
model dispatch. Preparation uses cumulative body, value-contract and work
limits; subtree hashing and typed reconstruction are charged separately.

The task and execution-contract identity fixtures use independent Node crypto
vectors. Regression coverage includes missing required fields, stale inner
CIDs under a freshly hashed environment, duplicate selectors, unsafe or
invalid settings, exact/one-short preparation limits, closed object contracts,
nullable success members and foreign environment handles.

This is a foundation for the shared inference owner, not a completed
acquisition path. The Program checker still refuses `infer` until checked
execution, capture and replay are connected. No B fixture was marked as a
successful packed inference, and no external model was called.

The complete `check_environment` package passed 201/201 tests on each of
JS, Wasm and native after adding the readers and regressions. After the
final typed-reconstruction precharge, all 201 JS tests and the nine affected
regressions on Wasm and native passed again. `moon fmt --check` and
`git diff --check` passed. The generated public interface passed
`scripts/check-moonbit-api.mjs` across JS, Wasm and native.
Full affected CI jobs and Linux CI remain unverified for this unit.

## Typed inference binding

`infer_typing/check.mbt` binds the exact admitted ModelTask, complete input
schema, candidate-key witness and typed INPUT expressions. It requires all
and only the closed task input roles, checks assignment compatibility and
retains expression validation obligations. Qualified Relation scopes use the
existing schema and expression scope rules, not flattened field names.

An explicit key must equal a whole non-null scalar candidate tuple. Subsets,
supersets and repeated components are rejected. Authored tuple order remains
a separate sidecar from canonical schema order. Omission requires a unique
candidate tuple, including alias alternatives; duplicate witnesses for the
same tuple remain retained rather than creating false ambiguity. Evidence
from an equal-shaped but independently admitted input is rejected. The
original witness keeps its producer and pending runtime validation obligations.

The output schema contains only the selected key fields and fixed outcome
and value roles. The success object retains its original child nullability;
only the outer value becomes nullable for failure outcomes. This schema is
not yet a produced-key proof or outcome-dependent refinement proof.

`relation_typing/check_count_value` exposes the existing count rule for the
infer author guard. It retains the exact parameter declaration owner and
deferred positive-safe-integer validation. No separate parameter parser,
resolved limit or Host authority is invented. Authored minimum classification
and result mode are likewise retained without granting model egress.

The final `infer_typing` suite passed 8/8 on JS, Wasm and native. The unchanged
`relation_typing` suite, including the new shared count-guard regression,
passed 274/274 on each target before the final qualified-scope test was added.
These are typing and admission tests, not model dispatch or packed acceptance.
Program integration, barrier preflight, call execution, capture, replay and
the existing Host dispatch connection remain unfinished. No external model
service has been called.

## Shared INPUT lowering and evaluation

`lowering_relation/prepare_infer_inputs` now prepares each admitted INPUT
mapping using the existing expression lowerer. Relation and acquisition
bindings share one implementation, including profile admission, typed object
fields, checked property ordinals, source locations and cumulative limits.
No second expression evaluator is added.

The infer owner retains its exact parameter declaration owner. Binding checks
use the same helper as ordinary Relation preparation: an equal-shaped foreign
declaration or missing required binding cannot substitute for it. Preparation
charges input entries, field resolution and expression work against one
budget rather than resetting the allowance for each role. The returned owner
does not admit call slots, classification, adapter transport or model access.

The mapped field, nested object/property and nullable parameter fixtures use
the existing resumable expression execution. Independent expectations cover
the existing 0.1 expression wire, string and NULL values, exact/one-short
preparation work, a foreign binding owner, and cancellation without destroying
the caller-owned input. These are input-expression tests, not a model call,
all-request preflight, capture or replay.

Verification of this source change:

- Complete `infer_typing`, `lowering_relation` and `execution_relation` JS
  suites: 1,294/1,294.
- Affected infer, parameter binding, expression lowering and object/property
  execution regressions: 38/38 on Wasm and 38/38 on native.
- Public interfaces regenerated from the integrated sources on all three
  targets; formatting passed.

## First runtime handoff

B's committed connection audit is
`0996714dfa283c428d9feb1e77f869ab94f9cd98`,
`docs/reviews/2026-10-01-infer-owner-connection-readiness.md` on B's branch.
It was inspected without adopting or modifying B's source or expectations.

The first adoption SHA must run the one-row INFER through the real public
Host. It will include a reproducible startup and deterministic physical
provider registration example, exact dependency bodies, input key admission,
finite limits, and an explicit list of unsupported forms. A standalone typed
owner or an injected finished Result does not meet that handoff condition.

The four remaining connections are ordinary Program inference admission,
produced key evidence for KEEP, physical ModelTask dispatch under the current
Host owner, and capture/replay with no replacement model execution. The first
Host connection can be handed off before the complete KEEP/replay matrix,
but those unfinished guarantees must remain visible. There is still no
adoptable full-Program execution SHA or public model registration example.
