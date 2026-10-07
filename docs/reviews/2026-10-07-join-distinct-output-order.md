# JOIN DISTINCT ordering from the evaluated output scope

Owner: B. Main baseline: `0916c24a4a0ec3f9652eae4a92770524aec0de58`.
Destination: main; no unmerged dependency. #701 and #703 are integrated.

## Counterexample and correction

```sql
SELECT DISTINCT -t.x AS x
FROM t JOIN r ON t.x = r.k
ORDER BY -x
```

For x=1,2 and matching r.k=1,2, the independent expected public x order is
-1,-2. ORDER reads the evaluated negative output x; using the original input
instead would reverse those rows. At the baseline, the projection-only JOIN
specialization refuses the computed ORDER expression. Focused red evidence:
`_build/focused-evidence/focused-test-lri38r`, 0/1.

`join_requires_group_scope` now selects the existing joined-row/scoped compiler
for non-FULL DISTINCT projections. That compiler materializes selected output,
applies DISTINCT only to those columns, derives private ORDER slots from the
evaluated output, sorts and removes helpers before publication. Removed inputs
remain unavailable. The existing FULL coalesced-key projection route is preserved;
this unit does not extend its computed DISTINCT ordering coverage. No expression,
checker, sort, capacity, provider, task or Result owner is added or relaxed.
Graph remains the sole current contract; no old identity or fallback is used.

## Independent fixtures and focused checks

The public fixture extends the existing DISTINCT corpus with five successes
and three refusals. Its hand-authored JSON control explicitly performs shared
Source JOIN, WHERE, negate/projection, DISTINCT, negate/sort, helper removal and
LIMIT/OFFSET. It is not generated from source compilation and is never patched
after lowering. Duplicate amounts, NULL, an excluded 99 and empty input make
wrong alias scope, lost DISTINCT or lost WHERE observably different. Full rows
are `[{amount:null},{amount:-1},{amount:-2}]`; LIMIT 2 OFFSET 1 gives
`[{amount:-1},{amount:-2}]`. The one public column is nullable number amount.

Focused JS passed 17/17 at the implementation tree, including INNER/LEFT/CROSS,
two explicit CTE producers, SQL/Pipe, existing expression reuse, JOIN-star and
DISTINCT callers. Four removed-column cases require UnsupportedOrdering.
Evidence: `_build/focused-evidence/focused-test-BvB2Io`.

An initial standalone CTE probe supplied its RHS as GeneratedValues rather than
the existing StageResult CTE input boundary and failed compilation. Explicitly
binding both inputs as CTEs passes ordinary checking. No CTE implementation was
changed, no D-owned repair is requested on that evidence, and no CTE public
execution success is claimed by the focused test.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/join_distinct_order_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/distinct_order_output_test.mbt \
  src/query_program/join_star_test.mbt
node scripts/packed-client-packages.mjs /private/tmp/actql-b-join-distinct-order-362417a09-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-distinct-order-362417a09-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache \
npm_config_offline=true npm_config_include=optional \
node scripts/test-packed-public-query.mjs --distinct-order-only
```

## Normal packed public acceptance

All five packages were normally packed at
`362417a0939494d26522f8cc6d6c5f9dcbba11ac`, using the pinned toolchain and
ordinary prepack. Embedded Local and public HTTPS each passed 11 successes and
6 preparation refusals, including the original unchanged cases. Checks retain
exact Named Result rows, describe type/nullability/column order, stream completion,
no private fields, shared acquisition once, same-request Run identity and no
extra acquisition on reread/attach. Refusals check zero Run admission/provider
acquisition. JSON and source Program layout/CID differences are allowed; no
old Run identity is reinterpreted. The runner's 11 profile checks and README/
missing-SDK-asset smoke checks also passed.

Evidence: `worktrees/.codex-scratch/public-query-evidence-SAjIM8`, passed and
complete, no evidence errors. Its temporary install was removed after saving
receipts/logs. The dirty flag is protected untracked review evidence; tracked
build inputs were clean. This following report commit changes no compiled or
public fixture input. Source and package identity are not relabeled as a new
runtime build or hosted CI success.

| Package | SHA-256 |
|---|---|
| client-wire | `0212e9f37cde525589a0e8d48b62151e73ce53153ef75948974cb9f672659523` |
| sdk | `fe085d7d7e2cce344c2c4daf18f33ca477dcee9189e96552816cf9eee6b10972` |
| run-host-core | `c30ec73dbc24d074d9d887b0eaab3387b95d55cd4b5ac11879cfe5775f7542de` |
| local-node | `052f029e96541deb71c8daacfc327b03b9780734c835fdd8561f59cb6ead14da` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Formatting of changed MoonBit and git diff --check pass. No full Core, Wasm/
Native execution, proof, performance, Cloud or manual CI campaign was run.
Keep Draft until content review and the required submitted-HEAD verification;
local public acceptance is separate from those conditions. No merge is performed.
