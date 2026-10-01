# INFER KEEP/AS: frontend and common-owner boundary

Base source: `6011cb8fb4bd85f832a62e16ff8358a45dcad44e`.
This unit implements source construction, not model execution. It preserves
the existing `actql-infer/0.1` and `actql.model_task/0.1` contracts. The common
infer owner is a separate implementation unit; no frontend evaluator, model
adapter, retry owner, capture ledger or stored format is added here.

## Source and independent Program

```sql
FROM tickets AS original
|> INFER `model-task:risk-score.v1`
     ITEM KEY (id)
     INPUT (text = text)
     KEEP (id, text AS note)
     AS assessment
|> WHERE assessment.outcome = 'ok'
     AND assessment.value.risk = 'high'
|> SELECT id, assessment.value.risk AS risk
```

The independently authored fixture is
[kept.expected-program.json](../../spec/frontend/fixtures/infer-keep/kept.expected-program.json).
[omitted.expected-program.json](../../spec/frontend/fixtures/infer-keep/omitted.expected-program.json)
covers omitted KEEP. Both use the ordinary Program admission boundary, with
one retained input producer, the existing flat infer operation, an explicit
one-to-one key join only when KEEP needs it, and ordinary object projection.
No additional acquisition is introduced by the join-back. INPUT alone is the
model-egress mapping; KEEP is neither an input mapping nor authorization.

The output scope contains KEEP fields in authored/expanded order followed by
the result alias. All older range variables are removed. Named key fields
remain inside `input_key`, including when no top-level key is kept. Source
construction checks names and collisions but cannot prove candidate keys,
authorize model egress or manufacture capture provenance.

## Public frontend operations

1. `query_syntax.parse_query(source, limits, source_path=...)` produces a
   bounded `Query`, with `Infer(InferClause)` retaining contract spelling,
   ordered keys, exact INPUT expressions, KEEP items and result AS name.
2. `query_program.compile(query, context, limits)` produces an admitted
   ordinary `stage_syntax.Program`. Context is the existing published input
   scope and parameter-declaration boundary; it does not install ModelTasks.
3. `query_expression.append_with_properties(...)` resolves a visible column
   or range prefix and emits ordinary property expressions. The common
   checker owns closed-object typing and nullability. This is not a schema
   inferred from a name or sampled row.

```moonbit
let parsed = @query.parse_query(source, syntax_limits,
  source_path="assessment.pipe").unwrap()
let program = @frontend.compile(parsed, published_context,
  construction_limits).unwrap()
// Required next boundary; constructing Program does not create a checked owner.
let checked = @check.check_parsed(program, environment, parameters, check_limits)
```

The prepared Host continues to call the existing checker and Run owner. The
SDK remains a lightweight source transport. It receives a typed refusal while
the common implementation is unavailable; no alternate execution path is used.

## Exact common dependencies and ownership

| Boundary | Current source behavior | Required common implementation |
| --- | --- | --- |
| Infer checking | `pipeline_typing/check.mbt` rejects infer as `UnsupportedOperation("infer")` | Resolve the exact ModelTask in the admitted Check Environment; check closed INPUT, scalar non-null candidate-key tuple, capacity and policy; issue the normal checked operation |
| Infer execution/capture | No checked Infer execution owner exists at the base | Admit/preflight all keys and fixed call slots before dispatch, execute the deterministic test ModelTask through the shared owner, retain attempts/accounting and captured outcomes, and replay without dispatch |
| Nullable property | Ordinary Values with a nullable closed object passes the common checker; `lowering_relation/expression.mbt` returns `ExpressionNotImplemented("property")` | Common bounded expression lowering/evaluation, including typed NULL propagation and unknown-field refusal |
| Object construction | The source uses existing `{object: ...}` expression meaning; common executable lowering is absent | Common bounded object projection with its checked contract and slot-bound evidence |
| Host/publication | No frontend-specific Host or provider is added | Use existing planner, Host, Result publication, delivery and cancellation owners once the common operation is available |

B owns `query_syntax`, `query_expression`, `query_program`, source/profile
documentation and independent frontend/public acceptance fixtures. A owns the
common checked infer and execution/capture implementation in its separate PR,
and the common object/property execution fix. Host integration must use the
existing owners, with C's active Host work kept separate. A must not implement
another parser or change the infer wire shape for KEEP.

The generic nested-reference probe is
[nullable_property_test.mbt](../../src/query_program/nullable_property_test.mbt).
It needs no model and distinguishes a successful shared type check from the
missing common expression lowering. Infer tests separately assert that no
checked/executable owner is manufactured by frontend construction.

## Required result, failure and provenance contracts

- Success `value` is the resolved non-null closed output object; each member's
  nullable contract is preserved. Non-success `value` is typed NULL.
- Outcome is exactly `ok` or the existing seven `failed:` classifications.
  Admission, authority, capacity, cancellation and engine failures remain
  barrier failures; they are not extra model-outcome rows.
- ITEM KEY must equal a proven non-null scalar candidate-key tuple. Duplicate
  identity and preflight failures cause zero provider calls. Empty input emits
  a typed empty Relation with zero calls.
- The existing owner retains policy, request, slot, input and capture identity.
  Renaming a column or replacing its value must not move capture evidence to
  another slot. Object projection must preserve the checked correspondence;
  the frontend does not supply a success-refinement or provenance certificate.
- Provider completion order has no semantic meaning. Reuse, attach, reread and
  replay must consume captured outcomes without issuing replacement calls.
- A deterministic test adapter must be connected to the common owner, not to
  the frontend or an acceptance-only execution substitute.

[expected-outcomes.json](../../spec/frontend/fixtures/infer-keep/expected-outcomes.json)
contains independent success/refusal/NULL/empty row and type expectations.
It is explicitly `not_run`, and is not an installed ModelTask contract or
captured provider evidence. No paid external-model acceptance is required.

## Reproduction and pending acceptance

Use the repository's pinned MoonBit toolchain and normal Node dependencies:

```sh
moon test --target js src/query_syntax/infer_test.mbt
moon test --target js src/query_program/infer_test.mbt
moon test --target js src/query_program/nullable_property_test.mbt
moon build --target js src/query_program_test_bridge
node --test scripts/query-program.test.mjs
node scripts/test-packed-public-query.mjs --infer-refusal-only
```

The packed command installs real artifacts outside the checkout and uses the
normal Embedded Local and HTTP Hosts. Its current scope is a working SQL
control plus typed INFER refusals, with zero new Run acceptance and source I/O
on refusal. It is not successful model execution evidence.

After A's fixed SHA is adopted, B closes success/non-success/nullable/empty
input, complete Result.describe contracts and column order, invalid key and
collision cases, immutable old scopes, cancellation, and duplicate-request /
reread / replay no-dispatch acceptance through packed Local and HTTP.
NEAREST KEEP, STEP/OP retirement and Cloud are outside this unit. Imported
historical acceptance cases are not marked executed by these new tests.
