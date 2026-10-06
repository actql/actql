# Statistical aggregate frontend connection

## Problem and scope

Baseline: `91ae3cb79fe7431e75fccfcb55a1ee59b84a5cc3`. The common aggregate
checker and runtime already support `var_pop`, `var_samp`, `stddev_pop` and
`stddev_samp`, including explicit ROWS analytic frames. Query aggregate
recognition and lowering omit these names. A pre-repair focused test accepted
an independently authored complete Program through the ordinary checker, then
failed compiling `SELECT VAR_POP(amount + 1) AS v FROM orders`.

The repair connects SQL SELECT, Pipe AGGREGATE and the existing explicit-frame
OVER profile to those same operations. `VARIANCE` maps to `var_samp` and
`STDDEV` maps to `stddev_samp`. It does not add a statistics evaluator, change
common arithmetic, increase ceilings or remove demanded argument failures.

Reference: [GoogleSQL statistical aggregates](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/statistical_aggregate_functions).
NULL exclusion, population/sample cardinality and aliases are selected from
that reference. The existing common finite binary64 law retains its canonical
value-CID observation order and rounded two-pass calculation. Wider numeric
coercions, nonfinite results, statistical DISTINCT and default analytic frames
remain gaps; this connection does not claim full GoogleSQL conformance.

## Independent evidence

- Pre-repair: 0/1 passed, compile failure after the independent Program's common
  checker acceptance (`run-XWLIcc`).
- New parser/lowerer checks: 5/5 passed (`run-kS4SQK`).
- Affected JS callers: 34/34 passed (`run-6WC8Kx`), including source routing,
  query recognition, existing COUNTIF/property aggregates and the fixed Run CID.
- Independent Node vectors and packed registration: 11/11 passed
  (`run-uagUOD`). An earlier caller test needed an explicit enum type annotation;
  an earlier Node registration assertion had a copied environment-name typo.
  Their failures are retained and are not reported as successful checks.
- Manifest freshness, document metadata and specification-family checks passed.
  Generated canonical identities were updated from their normative inputs.

Commands use the pinned toolchain and the existing bounded/nonzero wrappers.
The guard helpers and logs are retained under
`review-artifacts/b-statistical-aggregates-2026-10-06/` in the author worktree.
No full Core, Wasm/native, proof or performance campaign was run locally.

The existing packed public-query harness contains ten normal cases, five
preparation refusals and one demanded-expression execution failure per transport.
Normal cases cover an independent JSON control, SQL/Pipe expressions, sample
aliases, duplicate observations, a singleton, all NULL, empty input, grouped
HAVING/order/LIMIT/OFFSET and an explicit analytic prefix frame. Expected rows,
column order and nullable number contracts are authored independently. The
normal corpus includes these cases; `--statistical-aggregate-only` narrows the
same harness without altering cases or the installed capacity profile.

The harness checks rows and Result.describe, source acquisition counts,
same-request resubmission, attach/reread without additional acquisition and
preparation refusal before Run admission/provider I/O. Public execution remains
unverified until the clean-HEAD normal-pack producer and this consumer complete.
The submitted PR body records the actual fixed SHA, package manifests, receipt
and result; syntax/checker success alone is not execution evidence.

## Identity and remaining scope

Only the query text rules change the grammar manifest:
`33b5a9ea6214ae40f224b7f105632b933b6394dbd6d3f337cbdae20c9c1608ed`
becomes `cfb9547ce2d09997b65f3dc9496985e80c9e51210333b8dc7d5d911a0c3bb29d`.
The fixed Values Run CID becomes
`59d7c9a31639edee1087c0ba2e8dc6e2067e4730c4c7bfc14f41cebd065e0c90`,
derived from a hand-assembled preimage and independent dependency oracle.
Historical grammar/Run vectors remain intact. Unit, Result Plan, schemas,
operation registry and expression laws are unchanged. Dependent document CIDs,
manifest source and canonical vectors are regenerated together.

This is an independent Frontend unit on main with no unmerged dependency.
It does not close the overall SQL/Pipe/Graph/VecA/TEA migration, common-owner
coverage gaps or separate published Frontend PRs. Cloud is not exercised.
