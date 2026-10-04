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
- Initial fresh packed attempt at `8ab22b23db1beec2d19c8bcf9a996e89e2d6e4b2`
  (`public-query-evidence-sIJVnO`) stops before its first JSON control is
  accepted. That control omitted the installed acquisition's scan/filter/select
  shape; `prepare_client_query_acquisition` reports `UnsupportedShape`.
  Correct the independent control to an explicit always-true filter followed by
  select, retaining all rows and the same grouping/Result expectation. This is
  a control construction correction, not a change to a submitted source
  predicate, output expectation or common-owner admission rule.
- Fresh packed Embedded Local/HTTP: **8 positives and 3 pre-admission refusals
  per transport pass** at `81f3138626b5dd36a779e872d92ea19a7d4c6d09`.
  `public-query-evidence-wfzbpq` is complete/passed, with no evidence errors.
  Acceptance command 012 exits 0, signal null, with complete output (21.4s).
  The normally packed consumer runs outside the checkout without a MoonBit
  runtime. Successful temporary installations are removed after evidence and
  digests are retained.
- Exact submitted-HEAD automatic CI is pending; the preceding product's public
  success is not relabeled as final integration evidence.
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


## Normally packed distributions and integration

| Package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `6b448edf6ff246e1865858e9ed654e6f973c602e60b65447bcd7bbdd0afaefde` |
| actql-sdk-0.0.0-development.tgz | `a56cc9221e093a11a0557041fc28e62f8c7c0911689f3a0dd3964bd76d8029b0` |
| actql-run-host-core-0.0.0-development.tgz | `61c58a56eef782576b608178c38fb9bff7c550961cc39e6f6bbb458b21092fcc` |
| actql-local-node-0.0.0-development.tgz | `88cb3e3dcf50bf61296fb8571313d9755e7de0baf85cda54de84ee30d61c8539` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Subsequently integrated main `4319480319f492ee271799b83cb29a688fc311ad`
by normal merge without conflicts. This adds automatic-main CI scheduling and
its existing history declaration/tests. Frontend source, fixture and packed
consumer bytes are unchanged by that merge. No broad local rerun is added
solely for integration; exact submitted-HEAD CI verifies the combined tree.
There is no unmerged dependency on another Frontend or common-owner PR.
