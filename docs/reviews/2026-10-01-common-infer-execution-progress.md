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
| ModelTask admission | `check_environment` retains `ModelTaskContracts` as integrity-checked opaque members | Resolve one exact admitted task and its closed input/output contracts, generation configuration and data-handling policy |
| Checked operation | `program_check/check.mbt:check_supported_source` and `pipeline_typing/check.mbt` still refuse `infer` | Bind typed INPUT expressions, a proven non-null scalar candidate-key tuple, fixed output roles, capacities and success refinement |
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
contract baseline. Checker acceptance will not be broadened independently
of executable, captured and replayable semantics.

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
