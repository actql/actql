# SQL GROUP star input scope

## Selected defect and independent requirements

Baseline: `c7d44f0908587e894573370683fe38498eb7ae49` (`origin/main`).
This is an independent Frontend repair. It does not depend on #338's DISTINCT
ORDER repair or #346's ORDER positions and does not reopen the completed audit.

Before repair, the three selected tests fail (`run-wHkFKR`, **0/3**):

| Source, input columns `x,y` | Defect | Required behavior |
|---|---|---|
| `SELECT * FROM t GROUP BY y, x` | Publishes `y,x` in grouping-key order | Publish input order `x,y` |
| `SELECT *, COUNT(*) AS n FROM t GROUP BY x, y` | Expands star to `x,y,n`, then adds `n` again and refuses | Publish `x,y,n` once |
| `SELECT * FROM t GROUP BY x` | Silently removes ungrouped `y` and accepts | Refuse with `UnsupportedGrouping` |

These requirements come from the adopted GoogleSQL profile, independently of
ActQL output. The selected reference is
`d82db99a923a46571f543a13899dc791a7b6f743`:

- [SELECT star](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#select_star) expands visible input columns, in input order.
- [Independent aggregation analyzer cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/aggregation.test) require each expanded column to be grouped or aggregated; an ungrouped star column is an error.
- [Resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc) expands star during first-pass SELECT resolution and maps/checks those columns after grouping. It does not re-expand star against newly created aggregate slots.

## Repair and boundaries

`compile_steps` retains SQL grouping's original visible name/physical-slot
mapping. SQL star checks every original slot against the actual group keys,
then projects those columns in their original order. A new aggregate with the
same spelling cannot stand in for an ungrouped original value. Scoped JOIN
slots remain private and are projected under their existing display names.
An identity-SELECT optimization must not omit this post-group projection.

Pipe AGGREGATE continues to create a new output scope: its following SELECT
star includes the group keys and aggregate outputs in that scope. It does not
reuse SQL's saved input columns. A later Pipe operator after SQL SELECT still
consumes the projected current Relation. No grouping rule, presence/key proof,
checker, execution owner, provider, runtime or transport is duplicated.

The complete independent MoonBit Program expectation spells GROUP keys `y,x`
and SELECT/Result fields `x,y`. Caller cases include mixed star/COUNT in either
SELECT-list order, CTEs, scoped JOIN, aggregate/input-name collisions and
ungrouped columns. Refusals assert `UnsupportedGrouping`, not arbitrary errors.

The hand-authored public JSON Program and text cases are in
`scripts/fixtures/group-star-source-input.mjs`. Source schema order is
`amount,id`, while grouping order is `id,amount`. The duplicate ID 3 rows and
nullable amount give counted output:

```json
[{"amount":null,"id":1,"n":1},{"amount":20,"id":2,"n":1},{"amount":30,"id":3,"n":2}]
```

The existing packed consumer compares Named Result rows and `describe()`'s
ordered full column contracts, checks one acquisition session per source,
and requires attach/resubmit/read to preserve the Run without additional
acquisition. Refusals require existing typed input errors and zero Run
admission/provider I/O. Empty grouped input retains the declared nullable
schema without creating a global count row. No test-side Program correction
is used. These cases join the ordinary CI corpus; `--group-star-only` only
narrows the local execution.

## Executed verification and remaining coverage

- Focused JS `*GROUP*`: **8/8** (`run-2Po5x8`), including six new tests.
- Affected existing JS `*group*` callers: **6/6** (`run-hsEOmK`).
- Node public-case controls: **2/2** (`run-kFYqIv`).
- Pinned Moon formatting, Node syntax and diff checks pass.
- Fresh packed Local/HTTP is pending. Parser/checker evidence is not public
  execution evidence. Exact submitted-HEAD automatic CI is also pending.
- No full local Core, all-target, proof, performance or manual CI rerun.

Reproduce the selected public corpus with the repository-pinned toolchain:

```sh
node scripts/test-packed-public-query.mjs --group-star-only
```

The adopted contract is unchanged. No grammar, wire, schema, law/version pin
or public API is changed; generated Programs use their ordinary canonical
identity. Stored Program semantics remain unchanged. Group-key ORDER positions
are a separate Frontend coverage item, not implemented by this unit. A/C common
execution and D's CTE/assert/Effect branches are outside this diff.
