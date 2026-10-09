# Closed-object UNNEST Pipe edit column scope

Status: Frontend correction; independent lowering and limited JS checks complete.
Fresh packed execution and submitted-HEAD CI are recorded below when available.
Base: main `1b0ae88c87683b94cfd96e73f96f969cb4ecf355`; no unmerged dependency.

## Selected contract and conflicting historical expectations

The adopted GoogleSQL Pipe profile distinguishes a value-table column from
implicitly exposed object fields. The fixed reference checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`:

- [Column-target checking](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc):
  `FillItemStructFromNameListColumns`, `ResolvePipeSet`, `ResolvePipeDrop` and
  `ResolvePipeRename` distinguish named columns from value-table fields.
- [Independent reference cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/pipe_set.test):
  implicit fields cannot be SET targets; the whole value-table column can be
  replaced, becoming one ordinary column.
- [Name-list copying](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/name_scope.cc):
  replacement/exclusion applies to the whole named column; replacing a value
  table does not retain its previous implicit fields as current columns.

This is a correction under the adopted standards-alignment decision, not a
claim that historical ActQL UNNEST edit fixtures already had those semantics.
The earlier receiver record incorrectly treated SET of an implicit field as a
regular-column edit. Its old proof is historical, not evidence for this rule.
No live Google service differential was run.

For an object containing numeric `element` and `id`, these differ:

```sql
FROM UNNEST(@items) element WITH OFFSET position
|> SET element = 100
|> SELECT *
|> ORDER BY position
```

SET targets the whole named value-table column, not its same-named numeric
member. Output columns are `element, position`; the old `id` is absent.
SET/DROP/RENAME of the implicit `id` is rejected. Projecting `id` first creates
an ordinary column that can be edited without changing the original value slot.

Old fixtures are corrected with their original invalid sources retained as
negative obligations. The former whole-receiver preservation test now edits
`position = position + 10`, testing a real regular-column change while retaining
the original object. The former SET-id example explicitly projects its fields
and binds that ordinary row before SET; its expected current/original values
remain 12/2. No expectation is obtained from compiler output.

## Counterexamples and repair

Actual main diagnostic: receiver/range tests **7/8**, `run-PF36oC` /
`focused-test-rhX8ES`. The stale SET-element/property success fails checking.
New counterexamples before repair: **0/3**, `run-Z21kpo` /
`focused-test-upMBuK`: wrong whole-value SET star layout, implicit-field edit
acceptance, and incomplete whole-value DROP. The negative loop stopped at SET;
DROP/RENAME refusals were not individually executed before repair. An earlier
0/3 run also had a wrongly authored private-slot suffix; its correction did
not change expected public values, types or column order.

`unnest_pipe_edit_scope.mbt` supplies private column-target and star-layout
helpers. `compile_steps` uses them for SET/DROP/RENAME. Sibling SET values
still resolve against the original snapshot. Regular columns, surviving ranges,
parameter declarations and common property typing retain their existing owners.
No new evaluator, execution Owner, fallback, wire format or capacity exemption.

An additional empty-object case exposed `LocalConstructionFailure.Source`,
`run-nRbOrE` / `focused-test-7xHXMb`, after the edit correction. UNNEST had
already emitted its step, then emitted an empty operator-free step when there
were no fields to derive. It now omits that empty step. The empty object still
uses its admitted type; no row sampling or invented fields.

Complete hand-authored SET/DROP Programs pass the common checker before exact
comparison with lowering. Public fixtures add a separate normal JSON control,
quoted/noncolliding names, empty arrays, empty-object elements, object-valued
replacement, original-snapshot siblings, whole-value DROP and exact refusals.
The existing regular packed corpus includes every case.

## Limited verification

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/unnest_pipe_edit_scope_test.mbt \
  src/query_program/unnest_receiver_scope_test.mbt \
  src/query_program/unnest_struct_star_test.mbt \
  src/query_program/unnest_join_continuation_test.mbt \
  src/query_program/pipe_scope_test.mbt src/query_program/pipe_set_target_scope_test.mbt \
  src/query_program/pipe_set_window_test.mbt src/query_program/pipe_rename_target_scope_test.mbt \
  src/query_program/pipe_edit_range_collision_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unnest-source-input.test.mjs scripts/unnest-checked-array-source-input.test.mjs \
  scripts/spec-family-imports.test.mjs
```

- Final selected MoonBit checks: **41/41**, `run-RFZ5AC` /
  `focused-test-hjqVa4`. Ordinary Pipe and window callers included.
- Node fixture/normal registration/import checks: **11/11**, `run-uYpzYw` /
  `focused-test-zel8th`.
- Document metadata: no changes; actual links **1718 / 364 JSON files**,
  runtime_conformance:false. Changed MoonBit files formatted individually.
- Intermediate selection **38/40** identified the historical implicit-field
  controls requiring explicit projection. One subsequent diagnostic had an
  unbound test-only expected Program; no tests ran, and it is not a pass.

Common Program meaning, grammar, law/schema/registry pins and execution limits
are unchanged. Generated Programs differ because their scope is corrected.
D's CTE/assert/Effect/predicate functions and other worktrees are unchanged.
One existing Source routing condition receives formatter-only reformatting.

## Coverage remaining

This unit covers the existing closed-object UNNEST expansion. It does not claim
all value-table/anonymous STRUCT rules: scalar value-table RENAME still needs
its own target-scope review. Full Core/all-target/all-packed/performance and
live Google conformance remain unverified locally. The full public-text
Frontend objective remains active; parser/checker success is not public execution
completion or CI success. No merge is requested.

## Fresh packed public execution

Clean product/fixture SHA: `527feaf31e73d54fb771233e96c9c88d15b4f4af`.
Existing serialized bounded wrapper `run-2GrO5S` normally produced all five
packages, independently verified original SHA256 digests, and ran:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-unnest-edits-527feaf31-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-unnest-edits-527feaf31-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --unnest-source-only
```

No overlay, manifest relabeling or prepack bypass. Both Embedded Local and
HTTPS complete **73 positives / 29 refusal loops**. Sixteen explicit refusal
codes per transport are logged; the older broad-code checks are not mislabeled
as explicit-code logs. All new implicit-field and scalar-member refusals require
ClientProgramInvalidInput with zero Run admission and Source I/O.

The existing consumer compares complete rows, types/nullability/column order,
stream completion, hidden-column absence, acquisition counts and same-Run
resend/attach/reread without additional acquisition/execution. The independent
JSON whole-value control agrees with text. Empty arrays, empty-object elements,
NULL elements, object-valued replacement and sibling original-object access pass.
Whole-value SET exposes one ordinary column; whole-value DROP exposes only the
offset, without old members or helper slots. README Local/HTTPS and deliberate
missing-generated-asset checks also pass.

Receipt: `worktrees/.codex-scratch/public-query-evidence-pgFjlW`. Independent
inspection confirms exact revision, passed/complete, ten zero-exit complete
commands, no signal/error/evidence errors, all expected positive names and the
sixteen explicit refusal codes in both transports. `artifactsRemoved=true`;
logs/receipt retained, successful temporary installation and Stores reclaimed.

| Package | Original SHA256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | f5487ba69e88efbab8e99930482c27254b8055f421280045a46c0532f8349d1b |
| local-node | f9ef42b0d887fd169b5befb1c9263c291beb327b83c625d75d1a94bbee9ba0f9 |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

The subsequent evidence commit changes this report only. Submitted-HEAD CI
is checked after publication; local public success is not CI success.
