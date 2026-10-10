# PIVOT scalar aggregate arguments through the common expression path

## Requirement and independent counterexample

The selected [GoogleSQL PIVOT rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#pivot_operator)
allow an aggregate argument to reference input columns. Implicit grouping uses
unaggregated input columns other than the axis. This unit extends the existing
single-aggregate String-axis Pipe surface; it does not add all standard PIVOT
forms or a frontend aggregate evaluator.

At main `3c1aadc464205e66cd167b840833fa7474251a1d`, the following complete source
fails with Syntax("Expected operator clause delimiter"):

```aql
(SELECT 1 AS product,1 AS amount,'A' AS axis
 UNION ALL SELECT 1,2,'A')
|> PIVOT(SUM(amount + 1) FOR axis IN('A'))
|> ORDER BY product
```

Independent expected rows are `[{product:1,A:5}]`. Matched JSON Values rows,
an ordinary derive `adjusted=amount+1`, and common pivot with index=[product]
pass the existing checker. Retaining amount as an implicit group key would
incorrectly split this into two rows; dropping +1 would yield A=3. Baseline
`run-RLSIXc` is 1/2: JSON checks, source parsing fails. Preserve the minimum
source, expected Program and expectation at
`/private/tmp/actql-b-pivot-argument-expression-independent-control.json` and
`/private/tmp/actql-b-pivot-argument-expression-3c1aadc46-baseline.mbt`.
This is not evidence of an incorrect publicly executed result at that baseline.

## Connection and scope

PivotClause retains the ordinary Expression AST. Simple resolved column paths
keep the existing lowering. Other scalar arguments use append_pipe_expression,
one ordinary derive, and the existing common pivot. References are resolved
through current columns and immutable ranges; receiver slots are consumed for
property expressions. All referenced evaluated input slots are excluded from
implicit keys. A constant/parameter-only expression consumes no input columns.
An old range slot does not consume a different SET replacement slot.

The private argument slot is allocated against physical fields, current names
and authored bucket output names. It never becomes a user column or an implicit
key. Nested aggregates are explicitly refused using the parser's existing
aggregate-name inventory. Ordinary unknown-column diagnostics are retained;
property and arithmetic typing, NULL propagation and failure remain common
checker/expression responsibilities. No executor, capacity limit, identity
claim, authorization or consumer-side Program correction is added.

Independent public fixtures include matched JSON/source controls, two consumed
columns, a constant, old/current SET references, nullable arguments, an empty
bucket, an authored private-looking bucket, a typed parameter and nullable
object/property values. Refusals include consumed inputs, old ranges, unknown
references, an undeclared parameter, a nested aggregate and a wrong value type.
Existing public acceptance owns describe/rows, column order/contracts, repeated
request identity, no extra Source I/O and refusal before Run admission.

COUNT(*) is a separate pending PR #1343 at
`39e595066b7e47ddbaff31e1421cb8419834e734`, not an adopted dependency here.
Multiple aggregates, aggregate modifiers, non-String axes, NULL bucket constants
and FROM-suffix PIVOT remain separate coverage. Integrate the two grammar/API
changes together if that PR lands; do not revive a negative COUNT(*) expectation
on a main revision that supports it.

## Grammar and identity evidence

Use pinned moon info for query_syntax and the existing compilation-manifests,
document-metadata, spec-family and canonical generators. The grammar self CID
changes from 81c194e574cb92623e23bf9e81075a718e14111cdfcb0308507c4f6d0b6b0586
to 792dedb6f23299171b2a50f6a5bd26418a7e914a9c58b4303b4fd7c0b307ab14.
Values Unit, ResultPlan and Program identities remain unchanged. The grammar-bound
invocation template, executable, compiled Plan and Run change. Preserve the
complete predecessor grammar/dependencies/Program/Run in
scripts/fixtures/pre-pivot-argument-expression-values-identities.json. Its old
Run 0bf6c0cf5627553679b5bdf942fdd14f8f1f94f1d424d905b11f848339851094
is not reinterpreted under the new grammar. Current Run expectation
e071f9691fdb02ade889720e83d38c34c67f603e90e8a674406eb73bf2ac7fc7 comes
from independently assembled inputs and sorted-JSON hashing, not product output.
Current full preimages and the independent derivation script are retained in
/private/tmp/actql-b-pivot-argument-expression-current-run-preimages.json and
/private/tmp/actql-b-pivot-argument-expression-independent-vectors.mjs.

## Verification and remaining public gate

- run-Nq1VYm: focused parser/aggregate caller/ordinary PIVOT checks, 22/22.
- run-zNUavp: scalar-argument cases plus independently authored full Program, 9/9.
- run-U3NeZS: selected public syntax interface generation and normative generators.
  JS/Wasm/native interface compilation is covered; unsupported wasm-gc is skipped.
- run-2n1bYH: 29/32 while the update script had stopped before applying current
  identity expectations. Manifest 6/6 and public fixtures 5/5 passed. This is
  retained as a failed preparation check, not hidden as a product pass.
- run-jkGkgd: updated independent current/historical identity and grammar cases, 23/23.
- run-uGnZ8L: consuming Values Run identity checks, 2/2.

Normal clean-HEAD five-package production and --pipe-pivot-only Local/HTTPS
acceptance are the remaining gate at document creation. Record actual tarball
SHA-256 digests, source revision, child completion and Named Result comparisons
in the PR body; parser/checker success alone is not public execution completion.
No full Core/proof/performance/all-packed campaign or vendor differential is claimed.
