# Named WINDOW in Pipe SELECT

## Contract and baseline counterexample

Adopted main: `ffe46cdae6d064a60da517dec2937eeaee4a1c30` (already included).
The new branch retains parent #1115 at
`e93344ce715d29beb761f47541b9367067fd947b`; #1115 itself retains #1111.
The final target remains main; the child is not merged into a dependency branch.

The selected [GoogleSQL Pipe SELECT reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#select)
permits a WINDOW clause after the projection list. Names are visible only to
that operator. Inline window evaluation already worked, and independently
written common Programs passed the checker, but named Pipe SELECT failed parsing:

```sql
FROM t
|> SELECT x, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY y)
|> ORDER BY x
```

For independent input (x,y) `(1,20),(2,10)`, the result is
`[{"x":1,"n":2},{"x":2,"n":1}]`. The full independent Program explicitly
uses Analytic, Select and Sort; scalar window operands also compare against an
existing hand-authored full Program, without deriving expectations from output.
Baseline `run-sNn74n` / `focused-test-2HQUvb`: 1 passed, 2 failed. The checked
control and existing inline source agree; the two named-source tests fail.

## Local parser connection

The Pipe SELECT branch now parses its own WINDOW declarations, assembles its
existing Analytic/AnalyticExpressions and Select operations, and resolves only
that local list with the existing named-window resolver. It retains checked
inheritance, quoted/case-insensitive names, duplicate/conflict checks and earlier
declaration visibility. Used ordinary aggregate keys cannot introduce implicit
GROUP in Pipe SELECT. Unused declarations do not evaluate their keys or create
aggregation. No lowerer, common checker, analytic owner, execution format,
budget or Host routing is changed.

The same existing projection lowerer handles direct calls, scalar operands,
star replacements, immutable input ranges and evaluated output slots. Sibling
aliases are not input keys; projected/dropped columns and replaced ranges are
not revived. WINDOW names do not leak into the next SELECT/EXTEND; another
operator can reuse the name for a distinct window. Generated slots are not
accessible by authored names and do not become public fields. Existing window
signature/frame limits remain in force; naming does not add default frames.
Pipe WHERE with embedded window calls remains a separate Frontend gap.

## Independent public obligations

The existing normal and focused window-scalar corpus adds eight positives and
five exact ClientProgramInvalidInput refusals. Positives include independent
JSON, direct named SELECT, typed scalar operand, empty input, quoted inheritance,
consecutive local declarations, star replacement and nullable LAG arithmetic.
The independent JSON has the same analytic/sort arguments and public fields;
source-generated Programs are never patched by the acceptance application.

For input `(4,20),(1,NULL),(3,10),(2,20),(5,NULL),(0,999)`, WHERE id > 0
and analytic ORDER amount DESC NULLS LAST,id produce positions `[4,1,3,2,5]`
when finally sorted by id. The scalar +1 variant produces `[5,2,4,3,6]`.
Star REPLACE changes only amount to the non-NULL rank and retains column order
amount,id. LAG+1 produces `NULL,NULL,21,11,21`, with nullable output. Empty
results retain declared column contracts. The five refusals detect declaration
leakage, duplicate quoted names, a sibling output used as a window key, a dropped
range and attempted access to a private slot. Public checks require zero Run
admission and Source I/O for refusals, and compare Named Result/stream completion,
rows, describe types/nullability/column order, hidden fields, acquisition count
and same-Run resend/attach/reread counters on successes.

## Generated identities

Grammar changes from
`sha256:2d24701e5ceee0f06400e197124eb7d9c05b74b88de7bd76500820b04fe692ed`
to `sha256:621f06cc9ffc651a0d68da0b7994163bef2439b4b72a8608ccc480622e4c67d9`.
The independent canonical oracle derives Values Run
`sha256:02061c277b626444a02a26037851c14b49ea2fd7064a423eab92f17e3bc33799`.
The preceding grammar and complete Run preimages are retained in
`scripts/fixtures/pre-pipe-select-window-grammar.json`; historical `436bf4c3...`
and all earlier vectors retain their original meaning. Program/value contracts,
Unit/proof/ResultPlan are unchanged. Grammar-bound invocation, executable and
compiled Plan/Run identities change; saved old Runs are not relabeled.
Existing generators update compilation manifests, metadata/imports and canonical
vectors. Generated files are not hand edited.

## Executed checks and remaining scope

- Baseline: 1 passed / 2 failed (`run-sNn74n`, `focused-test-2HQUvb`).
- Initial parser connection and analytic callers: 19/19 (`run-RHQnmj`).
- Expanded scope/alias/frame/refusal callers: 31/31 (`run-8Y5Vxo`).
- Final selected JS plus Values publication identity: 32/32 (`run-kVJ2Id`,
  `focused-test-uVq6mk`). The new tests check exact UnknownReference,
  UnknownColumn and parser conflict reasons.
- Fixture, independent grammar/Run vectors and manifest checks: 21/21
  (`run-yinWZE`, `focused-test-8e16Q4`).
- Public fixture/document/import checks: 20/20 (`run-bMfo31`,
  `focused-test-4XN6uP`). All four existing read-only generator checks pass;
  382 canonical vectors match and metadata requires no further writes.
- Submitted-HEAD CI and three-target runtime execution remain unverified.
  Full Core, full packed and performance campaigns are not part of this unit.


## Fresh distribution evidence

Tested product/fixture SHA: `8069a8c2d39f111260553b95d8a345ee3e5cbdc3`.
Bounded serialized outer evidence: `run-CVxSFC`. Commands:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-select-window-8069a8c2d-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-select-window-8069a8c2d-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --window-scalar-only
```

Each Embedded Local/HTTPS entrance completed 40 positives, 22 preparation
refusals and one expected demanded-expression failure. The new named Pipe SELECT
contributes eight positives and five typed invalid-input refusals. The cohort
also retained the previous EXTEND and grouped/scalar-window checks.
All new expected rows/describe contracts and zero-admission/I/O refusals passed;
same-request resend and Result attach/reread retain counters and Run identity.
Existing untyped refusal helpers assert input errors and zero admission/I/O
without printing typed markers; 17 printed refusals per entrance therefore
represent 22 executed refusal fixtures.

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-piobhD`.
It is passed/complete, all ten child commands exit 0, no signals or evidence
errors, and successful external artifacts were cleaned after evidence persistence.
README Local/HTTPS quickstarts and the deliberate missing-generated-asset refusal
also passed. The original identified pack and evidence remain retained.

Manifest revision equals the tested clean checkout, and original tarball bytes
were independently hashed before consumption. SHA-256:

| Package | Digest |
|---|---|
| client-wire | `4105321db630741cba8d4573d9800f554af51b1b7eff46cdf17f651128ebcc9f` |
| sdk | `e4d0fff729f53b3cd96f97997c2bd052069d2de4152e083d84d4201852b46be6` |
| run-host-core | `5e3f4458e7cff82deae5225a95de3e3fb193b9a719c0b37b9a9663ff2b327f15` |
| local-node | `0efeec9543f8149931ce43e5024434f27c9295abdb206f3f32de34e07d0b3ded` |
| node | `aa96b83e047cf3fc42b560b578fc2a32b9a38fa3f32c62dcf9f5eaff26891f4b` |

The pinned focused pre-pack commands were:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/pipe_select_named_window_test.mbt src/query_program/named_window_test.mbt src/query_program/window_scalar_projection_test.mbt src/query_program/pipe_extend_window_test.mbt src/query_program/pipe_scope_test.mbt src/query_program/analytic_output_scope_test.mbt src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/window-scalar-source-input.test.mjs scripts/sga-query-call-contract.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/window-scalar-source-input.test.mjs scripts/document-validation.test.mjs scripts/spec-family-imports.test.mjs
```

The later evidence-only commit does not convert those local checks into
submitted-HEAD CI success. Draft preparation/full required CI, content review
and parent adoption are separate from this selected public acceptance. The
Frontend goal remains active; full GoogleSQL window coverage is not claimed.
