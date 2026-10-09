# Pipe RENAME: target scope and intermediate ambiguities

Date: 2026-10-09. Status: independent compiler counterexamples repaired and
focused packed Embedded Local/HTTPS acceptance completed. This does not establish
complete GoogleSQL conformance or completion of the whole Frontend objective.

## Selected meaning and defect

The adopted [GoogleSQL Pipe RENAME clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#rename)
requires each target to occur once in the current input row and preserves old
range bindings. The pinned reference is
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`:

- `googlesql/analyzer/resolver_query.cc::ResolvePipeRename` validates the
  targets before copying the name list with the authored rename map.
- `googlesql/analyzer/testdata/pipe_rename.test` explicitly accepts introducing
  an ambiguous output name; later lookup remains ambiguous. The atomic-swap
  control retains the original range values.

These sources select name/slot meaning, not a claim of live Google execution.
The original `compile_steps` instead required every intermediate output name
to be unique. Thus a unique RENAME target was rejected when unrelated JOIN
columns shared a name, and a new ambiguity could not be resolved by a subsequent
qualified projection. Ambiguous targets also produced the wrong generic
duplicate-output diagnostic.

Independent counterexamples include:

```aql
FROM pair AS old
|> RENAME x AS y
|> SELECT old.x AS original, old.y AS retained

FROM t AS l
|> RIGHT JOIN t AS r USING (x) MAX_OUTPUT_ROWS 10
|> RENAME x AS key
|> SELECT key, l.y AS left_y, r.y AS right_y
```

For pair `(x=7,y=9)`, the first returns `(original=7,retained=9)`.
In the second, x is the single coalesced USING key; two y slots are retained
independently. Full independently authored ordinary Programs specify all source
bindings, fields, JOIN ports, bound 10, projections and Named Result. Both
expectations pass the ordinary checker. They are not generated from the product.

## Localized changes

- Validate the authored targets against the same pre-RENAME visible row. Missing
  targets use UnknownColumn, ambiguous targets AmbiguousColumn, and repeated
  authored targets DuplicateOutput, matching existing current-column facts.
- Preserve duplicate intermediate logical names and their distinct physical
  slots. Rename does not change values or mutate immutable range snapshots.
- Require unique names at the existing final current-row export projection;
  an unresolved duplicate cannot become a malformed public Result.
- Select the existing joined-row scope lowerer for a JOIN containing RENAME.
  No new executor, acquisition, order mechanism, identity proof or fallback is
  introduced. D's CTE/assert/Effect/predicate implementations are not edited.

No grammar, schema, registry, canonical law or pin is changed. Normal Program
identity follows its actual generated structure. The work does not claim to
close every RENAME/range-shadowing or GoogleSQL name-resolution boundary.

## Fixed SHAs and limited checks

- Adopted main: `321db1b2c82f7c584e64920fa007c56204862a2c`.
- Parent #1135: `5a408764337aa3e5ad9bb0909cb88419f5365c2b`.
- Initial target/export repair: `bd2fede4a313daefef48642de6f20c9c7772e61a`.
- Clean final product/fixture SHA:
  `7cda2f6a2da82527ff114f5955cdb010b389cd61`.

Baseline `run-rpOymJ` / `focused-test-HJwcYn`: **1/4 passed, three failed**.
Two valid queries were refused; the ambiguous-target assertion also failed.
The target loop stops at the first failure, so later case variants were not
all independently observed before correction.

Intermediate `run-UrM93I` / `focused-test-G063vV`: **76/77 passed**. The new
independent self-JOIN expectation incorrectly captured t twice. Source inspection
confirmed the existing same-relation binding reuse; the fixture was corrected
to one producer imported by both consumers. JOIN values/ports, bound, output
types and rows did not change. Final selection `run-ggxFGx` /
`focused-test-QI8Wgc`: **77/77 passed**.

Node independent public fixtures/normal registration and machine imports:
`run-gYtBre` / `focused-test-A5zExc`: **7/7 passed**.

The first packed campaign at bd2fede4a stopped after **17 Local positives**;
no refusal cohort or HTTPS was reached. It preserves receipt
`worktrees/.codex-scratch/public-query-evidence-VhZMN0`. INNER JOIN plus RENAME
returned ClientProgramImplementationLimit during preparation. Focused baseline
`run-VjyKdX` / `focused-test-yV3sck` was 4/5; refinement
`run-A3ZdyC` / `focused-test-YHpCiC` confirms exact **UnsupportedCte**. The
projection-only JOIN entry expected SELECT before RENAME and never called the
existing scope-capable lowerer. This was a Frontend routing defect, not a common
capacity failure. No expected rows, predicates, keys or limits were weakened.

After that routing and diagnostic repair, `run-hkTA37` /
`focused-test-BQvCHV` passes **22/22**, selecting RENAME, JOIN ordering, RIGHT
JOIN, Pipe ranges and AS scope callers. Focused commands are:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/pipe_rename_target_scope_test.mbt \
  src/query_program/pipe_scope_test.mbt src/query_program/pipe_join_ranges_test.mbt \
  src/query_program/pipe_set_target_scope_test.mbt src/query_program/compile_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/pipe-join-ranges.test.mjs scripts/spec-family-imports.test.mjs
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/pipe_rename_target_scope_test.mbt \
  src/query_program/join_order_test.mbt src/query_program/right_join_test.mbt \
  src/query_program/pipe_join_ranges_test.mbt src/query_program/pipe_scope_test.mbt
```

## Final fresh public acceptance

Normal five-package producer and original digest verification run under the
existing bounded shared-heavy wrapper `run-xTlI1q`. It uses exact clean final
product SHA 7cda2f6a; no overlay, revised manifest identity or prepack bypass.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-rename-target-7cda2f6a2-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-rename-target-7cda2f6a2-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --pipe-join-ranges-only
```

Wrapper: `/private/tmp/actql-b-rename-target-7cda2f6a2-packed.mjs`.
Receipt: `worktrees/.codex-scratch/public-query-evidence-ANnCSF`, relative to the
workspace root. Independent inspection confirms passed/complete, the exact clean
revision, ten zero-exit commands, complete streams, no signal/error/evidence
errors and artifactsRemoved=true. Successful temporary installs/Host Stores
were removed after retaining original logs and receipt. README Local/HTTPS and
deliberate missing-generated-asset checks pass as well.

Embedded Local and HTTPS each complete **22 positives and 15 exact-code input
refusals**. All prior 16 positives/nine refusals remain. New obligations include
independent JSON, unrelated duplicate JOIN columns, quoted target, introduced
ambiguity resolved by original ranges, nullable values and empty typed output.
No failing case is excluded. Expected rows retain two `(20,2,2)` occurrences;
the nullable control additionally retains `(NULL,1,1)`. Declared columns are
current nullable number, original/matched non-NULL number, in that order.
Shared assertions check Named Result rows/schema, multiplicity, ordering,
private-field absence, one Source acquisition, same-Run resend/attach/reread
without additional acquisition/execution, and exact ClientProgramInvalidInput
refusals with zero Run admission/Source I/O.

| Original package | SHA-256 |
|---|---|
| client-wire | `9b29e7833f9c542bb966432d0889dc10b96e35a66e74b55afcafd546ca7f9e9e` |
| sdk | `1606b73984a8f32b3734040f0eac23fec4f7e25559ebdad5aac2a73d71fd966b` |
| run-host-core | `6a649f5f4755e0d651de62088f83d887369e0db5212130363f1cf909e69f7f15` |
| local-node | `17b5dc5fe4a4a833d7314b8736f595f1710eb36ce4318aac4c78e7b4f11f6fd1` |
| node | `029a16952028cf162eeb31a9ef2ee9074c337389569e23e8e4a7750d5adf5487` |

The submission commit adds only this evidence record. Submitted-HEAD CI is
recorded separately in the PR; neither the earlier SHA nor local packed success
is a CI claim. Full Core/all-target/full-packed/performance and live Google
differential execution were not run. Keep Draft pending dependency integration,
review and applicable verification. No manual retry or merge is requested.
