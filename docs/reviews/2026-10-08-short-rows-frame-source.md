# Single-boundary ROWS source connection

Date: 2026-10-08. Owner: B. Target: main. Status: implemented; selected source,
checker and identity checks passed. Exact-commit packed Local/HTTPS execution is
pending and must be reported separately. No merge approval is claimed.

## Missing connection and selected semantics

At base `59fe1e3eed0d07249121da4beb7b0378453cdd70`, the independently authored
complete Program for a preceding/current-row frame passes the common checker,
but its equivalent SQL/Pipe source fails to parse. The parser required BETWEEN
although the selected GoogleSQL syntax accepts one frame boundary.

```sql
SELECT id, SUM(amount) OVER (ORDER BY id ROWS 1 PRECEDING) AS running
FROM orders
ORDER BY id
```

The selected reference is `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`,
`docs/window-function-calls.md` and `googlesql/parser/googlesql.tm` (the
single-boundary `window_frame_clause` production). The
[official window function reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
also specifies the implicit CURRENT ROW upper boundary. This is selected-profile
alignment, not a claim of complete GoogleSQL conformance or a service differential.

`QueryParser::window_specification` now accepts a single ROWS boundary and
supplies `CurrentRow` only as the implicit end. Existing explicit BETWEEN parsing
and the authored start/parameter are preserved. Naming a window, using QUALIFY
or using a Pipe SELECT does not introduce a different frame meaning. No new
Program frame, execution Owner, sorting algorithm or wire format is introduced.
The normative EBNF also records existing UNBOUNDED boundary support.

Existing common checking rejects invalid intervals and parameter values before
Run admission. Positive numeric-distance requirements remain unchanged: zero
numeric bounds are a known common-contract coverage gap, not a GoogleSQL rule.
RANGE, default frames and row-dependent boundary expressions are not completed
by this connection. Those outstanding requirements are not deleted.

## Independent regression obligations

- `src/query_program/short_rows_frame_test.mbt` contains an independently
  authored full Program, checks it normally, and compares SQL and Pipe lowering
  with that Program. It checks the specific common InvalidFrame rejection for
  FOLLOWING starts, rather than accepting any error.
- `src/query_syntax/short_rows_frame_test.mbt` checks AST boundaries for numeric,
  declared-parameter, CURRENT ROW and UNBOUNDED PRECEDING forms.
- `scripts/fixtures/short-rows-source-input.mjs` contains a separate JSON
  control, unsorted input including NULLs, moving/cumulative/current-row
  expectations, a named-window extension, a declared bound, QUALIFY and empty
  typed input. None of its expected rows is generated from product output.
- The ordinary packed corpus and `--short-rows-only` selection contain the same
  9 normal and 5 refusal cases. The existing real Host harness checks rows,
  Result.describe contracts/nullability/declaration order, hidden-column absence,
  one acquisition and reuse without extra acquisition. Refusals must have the
  expected input-error code, zero admission and zero provider I/O.

## Identity and generated inputs

The grammar manifest is now
`sha256:de630432fb2b6f3700294801070100e3340fc6ad295c2671fe9c0b3222f16169`.
Its EBNF digest is
`f503d7097c17b26ce592fe87357441f6ea86420478f2a3e66b4fa765aa051fd8`
and rules digest is
`27fe4f563feb13443d7995f51f770399019e9645cbbc5a3105e0d0c48f870c73`.
The barrier manifest is unchanged. The resulting fixed Values Run CID is
`sha256:54454a972b8c176f336e748bff947d614133fc09e4e7ee9138492c7a0f2e748c`,
calculated by the independent, hand-assembled normative preimages in
`client-values-run-materials-vector.test.mjs`, not copied from the issuer.
Program/Unit/Result Plan meaning is unchanged; Run identity closes over the new
normative grammar. The old grammar/Run vectors remain pinned with their original
preimages. Saved old Runs are not reinterpreted as the new identity.

The existing compilation-manifest, document-metadata, spec-family and canonical
JSON generators refreshed derived artifacts. Generated files were not manually
edited. Read-only checks subsequently pass (380 canonical identities, 10 spec
family documents, 1,385 requirements, 267 machine imports).

## Local evidence before publication

Commands use pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e through the existing
bounded nonzero-test wrapper. These are working-tree checks, not CI or a clean
published-SHA campaign.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/short_rows_frame_test.mbt \
  src/query_syntax/short_rows_frame_test.mbt \
  src/query_program/analytic_frame_parameter_test.mbt \
  src/query_syntax/analytic_frame_parameter_test.mbt \
  src/query_program/named_window_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/sga-query-call-contract.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs \
  scripts/compilation-manifests.test.mjs scripts/spec-family-imports.test.mjs \
  scripts/frontend-profile.test.mjs scripts/short-rows-source-input.test.mjs
node scripts/compilation-manifests.mjs
node scripts/update-document-metadata.mjs
node scripts/check-actql-spec-family.mjs
node scripts/check-canonical-json.mjs
git diff --check
```

Initial red evidence: `_build/local-checks/attempts/run-oB4ny5` and
`_build/focused-evidence/focused-test-mrUVxb` (1/2: independent checker success,
source parse failure). Final focused parser/lowerer/parameter/named-window checks:
`run-2F8QFW` / `focused-test-7txuu9`, 13/13. Identity caller:
`run-mJpsRm` / `focused-test-oICp9z`, 1/1. Node pin/vector/corpus checks:
`run-0rRYMH` / `focused-test-yhkxCD`, 25/25. Four changed handwritten MoonBit
files match the pinned formatter. Earlier fixture-only construction/error-pattern
mistakes were corrected without weakening product checking.

## Next acceptance and remaining coverage

Commit the complete source/generated inputs, use the ordinary five-package
producer on that clean exact commit, independently verify all tarball digests,
then run `scripts/test-packed-public-query.mjs --short-rows-only` with the retained
packages. Publish exact source SHA, package manifest/digests and the separate
Local/HTTPS counts in the PR body. Preserve failed evidence if execution fails;
do not alter expectations or capacity ceilings to obtain a pass.

Full Core, other execution targets, whole packed corpus, proof/performance
campaigns and final submitted-SHA CI have not been executed by this selected
local verification. The broader Frontend goal remains open beyond this unit.
