# Pipe grouping member names

Base: main `dde7cca123b161d41e9a1e2b1093cb7cb49b611e`.
Branch: `fix/frontend-pipe-group-property-names`; merge target: main.
No unmerged parent or common-owner implementation dependency.

## Counterexample

```sql
FROM objects
|> AGGREGATE COUNT(*) AS n GROUP BY (payload).score
|> WHERE score IS NOT NULL
|> ORDER BY score
```

The independent ordinary Program derives a nullable numeric property, groups
by that evaluated value, counts all members including duplicates, then projects
the key as `score` before exposing `score, n`. The same complete source instead
exported `aql_group_key_0, n`, and a later reference to `score` was rejected.
The grouping/aggregate public-name collision check was also bypassed when the
aggregate was named `score`, because the grouping column retained its private
name. These are Frontend naming omissions, not common grouping failures.

The adopted GoogleSQL checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`. Its
`docs/query-syntax.md` implicit-alias rule names member access by the member;
`docs/pipe-syntax.md` AGGREGATE includes grouping columns before aggregates.
The [official Pipe reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#aggregate)
and [implicit aliases](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#implicit_aliases)
describe these rules. This connection does not claim full STRUCT, anonymous
column, explicit grouping-alias or shorthand-order syntax support.

## Minimal connection

`compile_steps` already resolves and evaluates Property grouping keys through
the ordinary expression path. It assigns a private grouping slot, preserves
NULL/value semantics, and closes the previous input range scope. Its displayed
key-name pass handled Reference nodes but omitted Property nodes. The fix uses
the Property leaf name there; the existing post-group projection binds that name
to the evaluated grouping key. It does not derive the property again, recover
an old alias, alter grouping equality or create type/order evidence.

The three new regressions fail before the fix: 0/3 (`run-3i0lkW`,
`focused-test-Vx4qgY`). The complete independent control passes normal checking
first. The test compares SQL and Pipe against separate complete expected
Programs: Pipe retains its existing final visibility projection after the
group-key rename, while SQL performs its selected projection. The first draft
used the SQL layout for both; source inspection of the existing final Pipe
projection establishes their structural difference. Neither expectation is
generated from the compiler or an observed Result.

## Public obligations

`scripts/fixtures/group-property-source-input.mjs` keeps its original independent
JSON control and all eight success/five refusal cases. It adds parenthesized,
quoted and computed Property receivers, current and retained SET snapshots,
post-group WHERE/ORDER/LIMIT, and an empty typed group. Four added refusals cover
group/aggregate and grouping/grouping leaf collisions, an AS-displaced input
range, and a prior input range referenced after grouping.

The independent ascending grouping result is:

```json
[{"score":null,"n":2},{"score":10,"n":1},{"score":20,"n":2}]
```

The NULL object and the object's NULL field share a NULL group; both 20-valued
rows contribute to COUNT. Public columns are `score` (nullable number), then
`n` (nonnullable number). Explicit ordering is used in the public fixtures.
After SET, the current receiver groups by other.score (100 through 500, count
1 each), while the retained range still groups the original nullable payload.
The post-group predicate/limit selects only `{"score":20,"n":2}`. Empty input
produces no groups with the same declared column contracts.

The existing `--group-property-only` selection and normal CI corpus use these
same authored inputs, without repairing generated Programs. The unchanged
consumer compares Named Result rows, full describe contracts/column order,
stream completion and absence of private columns; checks refusal admission/I/O
counts; and repeats, looks up, attaches and rereads the original epoch-bound
submission without extra acquisition. No client-wire fallback is added.

## Verification and scope

Pinned MoonBit `0.10.12+1634b282e` and Node `22.22.0` are used.

- `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program --filter '*GROUP property*'`: 12/12, `run-4b3JAr`, `focused-test-SinqYN`, pre-publication working-tree source. This includes existing receiver, grouping, type and work-limit regressions.
- `node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/public-query-profiles.test.mjs scripts/acquired-data-acceptance.test.mjs`: 14/14, `run-Dk15Gi`, `focused-test-oMEwE0`. These consuming checks validate the acceptance assertions; they are not actual Host execution evidence.
- The normal five-package producer and fresh external Local/HTTPS acceptance remain required on the clean submitted SHA. Earlier distributions are not substituted for this source.

All public runtime packages must come from the same clean submitted revision,
including client-wire. Borrowed yaml/esbuild dependencies are build tools only;
no checkout-linked ActQL runtime, old wire API or compatibility fallback is used.

This changes no parser grammar, common Program, checker, grouping owner,
capacity ceiling, serialization or contract pin. Full Core, Wasm/native,
required CI and all Frontend coverage are not established by these checks.
