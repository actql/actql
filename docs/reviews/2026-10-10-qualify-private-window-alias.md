# QUALIFY demand of an embedded SELECT window

## Reproduction and minimal repair

Dependency: PR #1177 at `e5a838a3c6e555daf04a29fe89dfb6bfc42c3852`.
Fetched main remains `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.
This branch does not depend on the separate Pipe-consumer PR #1181.

A checked schema supplies public numeric `id` and `aql_select_window_0`.
Rows `(id=2,user=10), (id=1,user=90)` separate the user value from rank.

```sql
SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos
FROM records
QUALIFY pos > 2
ORDER BY id DESC
```

The correct result contains only `(id=2,user=10,pos=3)`. The same query with
`GROUP BY ALL` has the same result on these distinct input rows. Both rejected
with `Expression(UnknownReference)` when QUALIFY demanded the embedded SELECT
expression before final projection. The QUALIFY alias materialization callback
appended private window bindings to input columns, reintroducing the ambiguity
that #1177 removed from final SELECT.

Only that callback now uses #1177's shared private-expression scope adapter.
The evaluated alias is cached by the existing materializer and reused in final
SELECT, not expanded or evaluated twice. Public schema fields and qualified
input receivers remain intact. Checker, evaluator, execution Owners, grammar,
contract identities and pins are unchanged.

The superficially similar ORDER-window callback was inspected. An alias
containing a window value is rejected before that callback when another window
tries to use it as an input. The exact existing `UnsupportedAnalytic` rejection
is retained by a focused test; this PR does not change that language boundary
or modify an unproven path.

## Independent expectations

- A complete hand-authored Values/analytic/derive/filter/select/sort Program
  passes the normal checker independently of source lowering.
- Focused lowering requires the add operand to be evaluated analytic slot 3
  (two checked fields plus the reserved output alias). The add occurs once.
- Lowercase and uppercase schema-only names retain public columns. Named
  windows, quoted aliases and explicit qualified user-value operands retain
  their distinct meanings.
- Eleven added public positives include ordinary JSON controls, both case
  forms, GROUP BY ALL, named/quoted syntax, NULL, empty input and duplicate
  rows. `QUALIFY pos > 2` retains duplicate id=2 rows with pos 4/3; comparison is
  multiplicity-aware. A qualified nullable user operand instead produces
  pos=91/id=1 and a nullable result contract.
- Two added public refusals cover a hidden QUALIFY slot and a window-valued
  alias used as another window input, with distinct existing error categories.
- The existing normal and narrow public consumer compares rows, full
  Result.describe types/nullability, declaration order, stream completion and
  request replay. No compiler-output-derived expectation, Program patch,
  new harness, Owner or fallback is introduced.

## Focused evidence

Paths are relative to this checkout unless absolute. Guard directories are
under `_build/local-checks/attempts`; test directories under
`_build/focused-evidence`.

- Before product repair: 0/2, exact `UnknownReference` in ordinary and grouped
  SELECT: `run-Kr1YRr` / `focused-test-tyHTYP`. This is lowering evidence, not
  a failed public Run.
- Minimal repair with existing caller tests: 23/23,
  `run-17aBm7` / `focused-test-q5Lkeh`.
- Expanded final JS: 26/26, `run-V6aQVF` / `focused-test-trBjLI`.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/qualify_private_window_alias_test.mbt src/query_program/qualify_test.mbt src/query_program/quoted_qualify_test.mbt src/query_program/select_window_private_scope_test.mbt src/query_program/window_scalar_projection_test.mbt`.
- Node fixture checks: 9/9, `run-uYmtT5` / `focused-test-Mfq83Y`.
  Command: `node scripts/local-checks.mjs test node -- scripts/window-scalar-source-input.test.mjs`.

The first expanded selection passed 25/26 at `run-kpSXrZ` /
`focused-test-TWCurJ`: the new named-window test mistakenly placed WINDOW before
QUALIFY. Correcting only the test to the existing clause order resolved it.
No grammar or product change was made for that test-writing error.

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used. Changed-file
formatting and `git diff --check` passed. The narrow corpus is now 81 positive,
39 refusal and one deliberate execution-failure case per transport.

## Remaining verification

Clean-source five-package Local/HTTPS acceptance for this child is pending.
Parent packed evidence is not child-HEAD evidence. Submitted-HEAD CI,
Wasm/native execution, full Core and the complete frontend campaign have not
been run locally. This unit does not establish completion of every frontend
semantic boundary. Final target is main after #1177 merges; keep the stacked
base until then. No merge or manual CI rerun is requested.
