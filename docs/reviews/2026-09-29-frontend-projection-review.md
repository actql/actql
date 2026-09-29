# Frontend projection review corrections

## Graph publication boundary

Graph path lowering uses private occurrence slots to bind nodes and edges.
Those slots are not a public Relation schema. Direct star over a path is
rejected with `query_program.UnsupportedProjection`, propagated by
`source_frontend.QueryLowering`, before a Program is returned for preparation.
An explicit projection establishes public columns; a later Relation star is
valid. A node-only pattern retains its existing `id` and property fields.
Quoted binding names follow the existing resolver. No field-prefix blacklist
is used, so explicitly named user fields are not silently removed.

The packed cases use an independently specified diamond graph and expect
`id` (number) and `name` (string), with exact rows for node-only star and
post-projection star. They execute generated JSON through the installed Local
and HTTP Host. They do not claim that raw source routing is already installed.
C owns the submit connection and its zero-admission/zero-provider-I/O test.

## Relation projection and ordering

Two additional counterexamples were reproduced from the current compiler:

```sql
FROM rows |> SELECT x |> WHERE x > 0;
FROM rows |> SET x = x |> SELECT x |> WHERE x > 0;
SELECT x + 1 AS a FROM rows ORDER BY x + 1;
SELECT x + 1 AS a, x + 1 AS b FROM rows ORDER BY x + 1;
```

The first and third compiled; the second and fourth were rejected. These are
implementation inconsistencies, not newly imposed language restrictions.
The adopted Pipe contract consumes the preceding operator's output Relation,
consistent with [GoogleSQL Pipe semantics](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#pipe_operator_semantics).
A SELECT after SET must not make later WHERE, EXTEND, SET or SELECT illegal.
ORDER BY may use an already evaluated output slot for an equal selected
expression; multiple distinct aliases do not make that expression ambiguous.
Existing output-name ambiguity checks remain. Sorting does not evaluate the
selected expression again, and DISTINCT still compares only public columns.

## Verification boundary

The focused query Program suite passes 70 tests after combining the fixes.
Packed Graph and combined projection acceptance are tracked separately and
are not established by those unit tests. The pre-fix routing SHA
`5ee0dec1747d6465e3829719a0adeca66caf427b` passed 243 Node tests and the packed
Node/browser smoke; its full Client job failed the separate Checkpoint
`crash-resume_claimed` recovery case (`preparing` instead of `succeeded`).
That run is not a complete Client gate pass or proof of a new Host regression.
