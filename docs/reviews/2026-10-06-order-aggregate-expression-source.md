# ORDER aggregate expressions through the existing Group owner

Owner: B. Parent #516 (`feat/frontend-select-aggregate-expressions`) at
`78e75b7bed4bbf3e579c002fbae4c75ad41a6af3`, including #509 and main
`64046e37a1cadb2148edeab7cbf85b96d125b518`. Keep the unmerged parent base;
the final merge target is main. This unit does not include sibling #512.

## First counterexample and selected contract

```sql
SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + 1, x
```

An independently authored complete Values/Group/derive/sort/select Program
passes the ordinary numeric checker on the parent. The same test then fails
while parsing source (0/1, `run-hA9v1E`). The complete expectation remains
unchanged after the fix; it includes both sort criteria and the final projection.

The existing adopted [GoogleSQL ORDER scope](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#order_by_clause)
and [aggregate call profile](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls)
are used. This connects implemented aggregate calls in SQL ORDER expressions
to ordinary Group, not a new executor or a broader analytic/modifier profile.

## Lowering and scope

The bounded aggregate-primary parser already used by HAVING and SELECT records
ORDER calls as private Group projections and retains source origins. Authored
SELECT projections remain unchanged. A call in SQL ORDER establishes global
grouping when the SELECT has no GROUP clause. Ungrouped selected inputs still
fail ordinary lowering. Aggregate calls are not introduced into Pipe ORDER,
analytic window-order or final set-output scopes; these remain explicit coverage
boundaries rather than approximated aggregation over an already projected row.

ORDER arguments share HAVING's pre-group SELECT-alias/input resolution. Thus
`SELECT -id AS id, SUM(records.id) AS total ... ORDER BY SUM(id)` aggregates
the alias's negative input values, whereas `SUM(records.id)` uses qualified
positive input values. Known calls are reused only when function, modifiers,
arguments and resolved value slots agree. Selected aggregate aliases cannot
be nested as another aggregate's input.

Scalar ORDER expressions consume evaluated call slots. The existing hidden-sort
projection removes private columns before Result publication. After DISTINCT,
ORDER must be determined by selected values; a removed aggregate is refused
with UnsupportedOrdering. Two parser-owned references to the same evaluated
aggregate can reuse an equivalent selected scalar expression. This equivalence
is deliberately limited to those private references: existing authored JOIN
expression spelling/reuse is unchanged. An intermediate caller failure in
`run-rqCqQg` identified an overly broad reuse change; it was narrowed without
changing that caller's fixture expectation.

A star can expose an input with a private-looking name that did not appear as
an authored token. The aggregate gets a separate physical slot. ORDER's parser
reference uses that slot, while star retains the original input value and its
public field. A second independent full Program fixes this allocation and
projection boundary. Compiling a parsed query twice must not append calls to
its authored HAVING array or change the Program.

No common Owner, Model/Effect wire, runtime progress/retention, capacity,
Graph contract, schema/law pin or public AST interface is changed. The existing
closed expression production and grammar manifest preimage are unchanged.
D's CTE/assert/Effect/cancellation/Model-wire work, H's identity/hooks/Ledger,
A's bounded execution and C's Graph implementation remain outside this diff.

## Independent public acceptance

The normal packed corpus contains an authored JSON control plus sources for
hidden COUNT sorting with WHERE/LIMIT/OFFSET, selected-call/HAVING reuse,
opposite alias versus qualified-input orders, DISTINCT scalar reuse, nullable
SUM sorting, empty global aggregation, CTE LIMIT/Pipe composition and typed
COUNTIF parameters. Expected rows and full ordered column contracts are
independent of product output.

Invalid DISTINCT ordering, nested aggregate aliases, ungrouped selection,
COUNTIF type and undeclared parameters must fail before admission/provider I/O.
A demanded divide-by-zero must not publish readable or describable Results.
The existing public harness checks Named Result values/order, Result.describe
types/nullability/column order, hidden-column absence, acquisition counts and
same-Run request resend/read/attach with no extra acquisition.

`--order-aggregate-expression-only` selects these cases in the same normal
tarball consumer. It does not patch generated Programs, overlay adapters,
raise ceilings or bypass producer prepack/manifest checks. Clean-SHA package
digests, commands and public results are recorded in the PR body and retained
external evidence after execution.

Focused working-tree evidence `run-CzhvV1` passed 95 query-syntax JS tests,
54 ORDER caller tests, 34 aggregate/HAVING caller tests and 13 Node tests.
This is not a full Core, Wasm/Native, proof, performance, Cloud or required-CI
claim. Final clean-SHA execution is recorded separately.
