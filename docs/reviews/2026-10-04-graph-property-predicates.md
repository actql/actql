# Nullable object properties in definition-scoped node predicates

## Scope and baseline

This independent branch starts from main
`7e32faa5a455dc4beafa02a8cd06313e83772d50`, including #388's Draft CI policy.
There is no unmerged code dependency. It repairs the node predicate entry in
`keyed_node_constraint`; Graph construction, labels, identity, checker,
provider, physical strategy, acquisition, snapshot, SDK and diagnostics owners
are unchanged. D's CTE, assert, Source predicate and Effect implementation is
not edited.

The adopted [Graph pattern scope](../spec/query-text.md#graph-pattern-source)
places the initial predicate in its definition-scoped property environment.
The existing common `match_nodes` contract accepts structured expressions and
closed nullable objects. A field's typed NULL is distinct from a missing field;
missing members and non-object receivers remain common type errors. Static
label membership is independent of all property values.

## Independent counterexample

```aql
DATA g = PROPERTY GRAPH (
  NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))
);
FROM GRAPH g
  |> MATCH WALK (a:Person WHERE a.payload.score > 10)
  |> SELECT a.id AS id
```

The [handwritten complete Program](../../src/query_program/graph_property_predicate_test.mbt)
uses Values rows with ID/score pairs `(2,10)`, `(1,20)`, a NULL receiver at ID 3
and a NULL member at ID 4. Its ordinary checker accepts the Graph construction,
definition-scoped match predicate and Result. The equivalent text previously
failed with `Expression(UnknownReference)` in scalar-only lowering. Baseline
**1/2**: `run-8rRk0O` / `focused-test-vrDEff`. A separate focused failure
`run-2Ik34I` / `focused-test-SuYKXX` identifies the exact reference error.
An intermediate test diagnostic attempted Debug on the outer Issue, which
does not provide that trait; this test-only compilation error was corrected
and is not successful verification.

## Repair

Use the existing `append_with_properties` expression entry while retaining
`keyed_property_field` as the scope resolver. The longest admitted column or
variable/column prefix becomes the receiver; the remainder becomes an ordinary
structured property expression. No expression text is reparsed, no property
type is guessed, and no predicate is substituted or pre-evaluated. Both WHERE
and the existing property-map constraint entry share this repair. Labels still
lower independently to `match_nodes.label`.

The common checker retains exact missing-member and closed-object-receiver
errors. The existing expression budget and original source origins remain.
Qualified/backtick/local references and anonymous node constraints reuse the
same existing binding rules. A later output alias and another pattern variable
do not become visible inside the initial constraint.

This unit does not connect nested Graph properties in SELECT/ORDER expressions,
edge predicates or unsupported intermediate/endpoint pattern bindings. Those
are separate Frontend/Bridge boundaries; this predicate repair does not make
them executable or redefine them as invalid target-language syntax.

## Public acceptance obligations

The [public corpus](../../scripts/fixtures/graph-property-predicate-source-input.mjs)
has nine positives (one independent JSON control and eight authored text inputs)
and five preparation refusals. All source inputs use the adopted DATA/property
Graph/MATCH syntax and the ordinary public Client; no generated Program is
patched. Independent expectations distinguish `score > 10` (`id=1`), NULL
receiver or member (`id=3,4`), three-valued OR (`id=1,3,4`), typed empty output
and an explicitly declared numeric threshold. Explicit ID order and a single
nonnullable numeric public column apply, including to empty results.

The normal packed corpus includes these cases. The focused selection is
`node scripts/test-packed-public-query.mjs --graph-property-predicate-only`.
It retains normal prepack, external install, digest/source identity checks and
the shared Local/HTTP application. That application checks full ordered
`Result.describe()` contracts, rows, hidden-column exclusion, stream completion,
same-Run resubmission/lookup/attach and no additional provider acquisition.
Foreign receivers, missing properties, scalar receivers and prematurely used
output aliases must retain typed preparation refusals with zero durable Run
admission and zero provider I/O. These are obligations, not execution claims.

## Executed evidence and remaining work

New focused JS tests pass **8/8** (`run-S0252w`, `focused-test-KPYn8c`).
Existing keyed property callers pass **4/4** (`run-Fgb26R`,
`focused-test-QqH6qI`). The former covers full-Program equality, qualified,
quoted, local and anonymous scopes, common predicate composition/property maps,
exact UnknownReference origins, common `UnknownField("missing")` /
`TypeMismatch("closed object receiver")`, and the existing expression WorkLimit.
The latter retains the existing static-label/property distinction and canonical
top-level property spelling. Expected Programs and rows were authored from the
contracts rather than compiler or provider output.

Packed Local/HTTP and submitted-HEAD CI are pending. No grammar, wire, schema,
law CID, storage or contract-version change is introduced. Full Core, all
targets, proof, performance and a Google service differential run are not local
checks for this bounded unit. Draft preparation is not merge validation;
`awaiting ready_for_review` is not a rerun request. No merge is performed.
