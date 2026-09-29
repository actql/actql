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

The final tested source is
`fc5d0e469e167b919f0adce9d7b3a3e0e6f5aec2`. The following checks passed:

- `moon test --target js src/query_program`: 70 tests (same product tree).
- `moon test --target js src/source_frontend`: 5 tests (same product tree).
- Both packages on `wasm` and `native`: 70 and 5 tests respectively.
- `node scripts/local-checks.mjs run lint`.
- `node scripts/test-node-client-package.mjs --projection-only`: packed Local
  and HTTP, including exact public fields and independent expected rows for
  Graph stars, post-SET projection operations and equal selected expressions.
- Script syntax, diff whitespace and document links.

Graph-only packed acceptance also passed at
`552678c8cff1009ca0fb603266964142c678b2a3`. Native compilation initially stopped
because the configured workspace scratch directory did not exist; it passed
once that directory was created, without source changes. The first focused
packed harness needed to restore its original fetch function before HTTP;
the fixed harness passed on the final tested source above.

No Linux CI result is asserted. The pre-fix routing SHA
`5ee0dec1747d6465e3829719a0adeca66caf427b` passed 243 Node tests and the packed
Node/browser smoke; its full Client job failed the separate Checkpoint
`crash-resume_claimed` recovery case (`preparing` instead of `succeeded`).
That run is not a complete Client gate pass or proof of a new Host regression.


Tarball SHA-256 digests from the final tested source:

| Package | Digest |
| --- | --- |
| client-wire | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| sdk | `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515` |
| local-node | `3085a41b3803d62246c28cc0231d30eff009ddd1fb2fca85ab17f9748f173200` |
| node | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

The rejection is established at the pure source-lowering boundary. The raw
source public Host's zero-admission and zero-provider-I/O acceptance remains
with C's pending connection; the packed cases above submit generated Program
JSON and do not substitute for that acceptance.
