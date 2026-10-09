# JOIN current-row operators before projection

Base: `040eed2b1a11a3d1f7bae81b68d956d1017fac05` (main).
Status: focused lowering checks pass; packed public execution is not yet verified.

## Defect and repair

An INNER JOIN followed by ORDER, LIMIT, two WHERE operators, or AS before
SELECT parsed successfully but failed in the public script lowerer. The
projection specialization accepts only an optional single WHERE followed by
SELECT. `join_requires_group_scope` did not account for that applicability
condition, so valid current-row queries reached the incompatible specialization.

The independent complete Programs check successfully before the source is
compiled. At the unchanged base the four original tests failed in
`compile_query_script`; this is compiler evidence, not an executed failed Run.
Evidence: `_build/local-checks/attempts/run-pQ058J` and
`_build/focused-evidence/focused-test-ISfEBg` in the B worktree.

The repair routes queries whose prefix is not that specialization's supported
shape to the existing shared JOIN scope and ordinary operation compiler. It
neither moves predicates across takes nor invents an execution operation.
JOIN keys, the explicit ceiling of 10, parameters and input ownership remain
ordinary Program contracts. The ordinary projected JOIN specialization remains
available for its supported prefix. No common contract, pin or generated API
changes are required.

## Contract and independent counterexamples

`docs/spec/query-text.md` defines ordinary Pipe scope, range replacement at AS,
projection materialization and parameterized LIMIT/OFFSET. The pinned GoogleSQL
reference (`d82db99a923a46571f543a13899dc791a7b6f743`,
`docs/pipe-syntax.md`) describes chained JOIN and current-row operators. This
repair introduces no new syntax or meaning.

The source input deliberately starts in an unsorted order and contains a
NULL amount and duplicate id=3 rows. The right Relation contains k=1,2,3.
All source cases keep `ON records.id = keys.k MAX_OUTPUT_ROWS 10`.

- Sorting by id and taking count=2, offset=1 before projection returns
  `[{"amount":20,"id":2},{"amount":30,"id":3}]`.
- Sorting, taking count=1, offset=0, then filtering k=3 returns no rows.
  Filtering k=3 before that take returns `[{"amount":30,"id":3}]`.
  Moving or omitting a predicate therefore cannot pass both controls.
- Consecutive predicates retain the two id=3 rows, without DISTINCT.
- AS current replaces both input ranges; references to records or keys afterward
  are refused. The fresh (including quoted) range selects the current row.
- Omitting SELECT retains amount, id, k in that order, without internal columns.
- Empty Source input retains the declared Result columns; nullable amount is
  preserved. An invalid count is rejected before admission and Source I/O.

Complete common JSON controls and expected rows/contracts are hand-authored in
`scripts/fixtures/limit-parameter-source-input.mjs`. The query tests independently
specify complete lowered Programs and compare semantic representations. They
also check the actual script entry and common checker, including precise
UnknownReference refusals for displaced ranges.

## Focused verification

Use the pinned Node and MoonBit toolchains recorded by the repository.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_current_row_prefix_test.mbt \
  src/query_program/join_pipe_limit_tail_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/limit_parameter_test.mbt \
  src/query_program/captured_join_projection_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/limit-parameter-source-input.test.mjs
```

- JS: 22/22, including six new prefix tests and affected existing callers.
  `_build/local-checks/attempts/run-cWWGQ0`;
  `_build/focused-evidence/focused-test-z2Obwr`.
- Node: 7/7, including authored operator-order and visible-column controls.
  `_build/local-checks/attempts/run-dvtrQW`;
  `_build/focused-evidence/focused-test-DRgeGQ`.
- The first four repaired tests also passed 4/4 in `run-7ZuizW` /
  `focused-test-VLW06S`.

## Public acceptance and remaining coverage

The existing `--limit-parameter-only` consumer now includes 32 positive and
19 refusal cases per Local/HTTPS, with 11 new positives (three JSON controls)
and three exact-code refusals. These additions are also registered in the normal
packed corpus; the focused selector is not their only entry.

The existing public harness compares Named Result rows and describe column
contracts/order, verifies Source sessions, same-request resend/reattach/lookup,
and checks no extra Source I/O. Preparation refusals retain the zero-admission,
zero-I/O checks. No Program correction or adapter overlay is used by tests.

Normal five-package production and focused Local/HTTPS execution are pending.
Full Core, Wasm/Native execution, full packed campaigns and submitted-HEAD CI
have not been performed for this unit. Passing one cohort does not establish
completion of the full frontend goal.

## First packed attempt: fixture parameter correction

The clean source `edd0b53a04f06bb7df32d8d54d055bedc2686878` produced all
five normal packages. The Local consumer passed the existing LIMIT cases and
the new JSON controls, ORDER/take, unprojected current row, and both
WHERE/take-order cases. It stopped at `join-prefix-consecutive-where` with
`SubmissionNotAccepted / ClientProgramInvalidInput`. Remaining Local cases and
HTTPS were not reached in that attempt.

The fixture inherited count/skip declarations and values although that source
has no LIMIT or parameter reference. The common usage checker already rejects
unused parameter declarations (`program_check/template_declarations_test.mbt`).
A diagnostic against the freshly built preparation bridge and the public
harness's admitted Source environment confirmed `check_invalid_input` for the
declared form and readiness when those unused declarations/values were absent.
This diagnostic is not an additional packed execution claim.

Remove only the unused fixture declarations/values in that case and the two
AS range-refusal cases. Keep their text, predicates, ceiling and expected rows
unchanged. The range refusals must exercise reference scope rather than unused
parameter declarations. The new MoonBit refusal tests already check the exact
UnknownReference issue in both query and script compilation.

Original failed receipt/logs: `../.codex-scratch/public-query-evidence-BMxXuH`,
particularly `010.stderr.log` and `010.stdout.log`; serialized guard
`_build/local-checks/attempts/run-C4i8qW`. The receipt identifies the clean SHA,
tarball digests and completed failing command. It is retained as failure
evidence and is not counted as successful public acceptance.
