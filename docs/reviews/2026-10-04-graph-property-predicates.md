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

Changed MoonBit formatting, three Node syntax checks, local document links and
`git diff --check` passed.

Clean normal pack from
`1ae1a3f260a1759e462fbb27919e936f54424367` completed the focused selection:
**9 positives + 5 preparation refusals on Embedded Local, then the same
9 + 5 on HTTP**. Receipt `public-query-evidence-9xoeqS` records status passed,
complete true, all 12 command exits zero, source identity and tarball digests.
The positives include the independent JSON control and authored source, not a
test-side Program patch. Both routes compared independent rows, full ordered
Result descriptions (including typed empty output), finished streams, public
fields, same-Run resend/lookup/attach and acquisition counters. The five refusal
cases verified existing typed public input errors, zero Run admissions and zero
provider I/O. Preliminary README Local/HTTPS controls also passed; they are
separate from these Graph acceptance counts.

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `65b6408c2bb93597b8c92fc424b010b5e1d3e8b75ba414ad006bd30d57999a86` |
| local-node | `a0551d47c34a7ef59c7042227ed128f922d4e5994771715bfdd305ba2264d45d` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

After completion, the original command evidence and package digests were kept,
and only this invocation's temporary installation was removed (about 178 MiB).
Its separate cleanup record does not rewrite the original receipt. No shared
dependencies, toolchain, another worktree or active output were removed.

Submitted-HEAD CI remains unverified. No grammar, wire, schema, law CID, storage
or contract-version change is introduced. The evidence commit does not modify
the tested product, fixture or harness, so no second packed run is added solely
for the report. Full Core, all targets, proof, performance and a Google service
differential run are not local checks for this bounded unit. Draft preparation
is not merge validation; `awaiting ready_for_review` is not a rerun request.
The source-to-Named-Result boundary above is locally accepted; review and
required submitted-HEAD CI are separate. No merge is performed.
