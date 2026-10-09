# JOIN current-row operators before projection

Base: `040eed2b1a11a3d1f7bae81b68d956d1017fac05` (main).
Status: focused lowering checks and packed Local/HTTPS acceptance pass at
`4553f6a51f90052ca3b80d05dbde1ba678f3f5cd`; submitted-HEAD CI is not established.

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

Normal five-package production and focused Local/HTTPS execution succeeded at
`4553f6a51f90052ca3b80d05dbde1ba678f3f5cd`. Full Core, Wasm/Native execution,
full packed campaigns and submitted-HEAD CI have not been performed for this
unit. Passing one cohort does not establish
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
declared form and no preparation issue when those unused declarations/values
were absent.
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

## Successful packed acceptance

Packed source: `4553f6a51f90052ca3b80d05dbde1ba678f3f5cd`, clean HEAD.
The product MoonBit source is unchanged from the 22/22 focused JS check;
the fixture correction was checked again with Node, 7/7:
`_build/local-checks/attempts/run-2u88wd` and
`_build/focused-evidence/focused-test-0CiEX8`.

One serialized 1200-second guard executed the normal producer, independent
digest verification and existing focused consumer:

```sh
node scripts/packed-client-packages.mjs \
  /private/tmp/actql-b-join-current-row-prefix-4553f6a51-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-current-row-prefix-4553f6a51-pack \
  node scripts/test-packed-public-query.mjs --limit-parameter-only
```

Guard evidence: `_build/local-checks/attempts/run-nWMqcG`. Original public
receipt and command logs: `../.codex-scratch/public-query-evidence-Y8ol88`.
The receipt records the clean source SHA, all ten commands with status 0 and
complete output, no evidence errors, and successful artifact removal. The
temporary installation directory is absent; original receipts and logs remain.

Both Embedded Local and HTTPS completed all 32 positive and 19 refusal cases
through the ordinary public SDK/Host. Seven refusals assert exact codes (the
three new ones use ClientProgramInvalidInput); twelve retained older fixtures
use the existing accepted input-error categories. Neither is presented as
coverage of a specific diagnostic it does not check. Positive cases compare
Named Result rows, full column contracts/order and hidden-column absence;
resend/reattach/lookup preserve the Run and add no Source I/O. Refusals check
zero Run admission and zero Source I/O.

The five receipt digests match the normal producer manifest:

| Package | SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54 |
| local-node | 9b09ca1b9fcb24735922d54077dc1afb17cb5d7cf50f36332b0847403cdb72e3 |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

The subsequent evidence-recording commit changes only this document. Its
submitted SHA and exact workflow observation belong in the PR body; this
packed evidence remains attributed to the source SHA above.

## Additional caller: JOIN ORDER-only analytic input scope

An additional caller audit used the same current main,
`040eed2b1a11a3d1f7bae81b68d956d1017fac05`. Three SQL JOIN sources with an
ORDER-only ROW_NUMBER window failed in script compilation. The independently
written common JOIN/analytic/sort Program and a projected Pipe counterpart
passed: 2/5 at main (`run-0TFQeF`, `focused-test-73RirS`). This is a
lowering failure, not evidence of a publicly executed failed Run.

The SQL parser inserts OrderAnalytic before SELECT so it can resolve
unselected input fields and evaluated SELECT aliases in the proper clause
scope. It therefore reaches the same unsupported specialization prefix. The
existing repair closes this caller without any additional implementation:
5/5 on the repair branch (`run-hZgdbp`, `focused-test-Zk675I`).

Further tests keep projected-away Pipe input ranges rejected with the exact
UnknownColumn issue in both query/script compilers. The common OVER-key
resolver owns this direct-column issue; it is not the property-expression
UnknownReference diagnostic. An initial test incorrectly assumed the latter
(14/15 in `run-q71O9g` / `focused-test-s1c2uB`); an attempted generic Debug
probe then failed to compile because Issue has no Debug implementation
(`run-GFdzMh` / `focused-test-aNJHZR`, no tests executed). Neither altered the
product. Source inspection and the final precise test establish the existing
UnknownColumn contract. Final focused checks:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_order_window_test.mbt \
  src/query_program/order_window_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/order-window-source-input.test.mjs
```

- JS 15/15: `run-U8DOK1`, `focused-test-HWXVb9`.
- Node 3/3: `run-Lddain`, `focused-test-suAGth`.

The existing ORDER-window corpus receives eleven positives (including three
independent complete JSON Programs) and one exact-code projected-input
refusal. There are now 25 positives / 8 refusals per Local/HTTPS. The authored
WHERE, JOIN key, ceiling 10, parameter operand, LIMIT/OFFSET and Result
columns are preserved. The alias control orders the evaluated negative amount;
the qualified control orders the original amount. Their independent orders
differ (after the two NULL rows, id 3/4/2 versus id 4/2/3), so wrong reuse
cannot pass both. LEFT JOIN keeps unmatched right keys nullable. Duplicate
Source rows and typed empty input are separate obligations. The original
ORDER-window corpus remains unchanged, and the additions are included by its
normal packed registration.

The previous LIMIT-prefix public receipt remains evidence for its own source
SHA. Fresh normal-package ORDER-window public execution completed at the source SHA
below; the scoped compiler checks and public execution remain distinct evidence.

### ORDER-window public result

Clean packed source: `77f34f3724387a4a13ef067e40394b01180927c3`. One serialized
1200-second guard (`_build/local-checks/attempts/run-WZUIbI`) ran the ordinary
five-package producer, independent manifest/digest verification and the existing
focused consumer:

```sh
node scripts/packed-client-packages.mjs \
  /private/tmp/actql-b-join-order-window-77f34f372-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-order-window-77f34f372-pack \
  node scripts/test-packed-public-query.mjs --order-window-only
```

Original receipt and command logs: `../.codex-scratch/public-query-evidence-ATraSc`.
Both Local and HTTPS passed 25 positive and 8 refusal cases. Four refusals
assert exact codes; four retained fixtures use the existing input-error
categories. The new projected-input refusal is ClientProgramInvalidInput,
with no Run admission or Source I/O. All positive JOIN cases reach Named Result,
compare independent rows/column contracts/order and hidden-column absence,
and preserve one Source session plus same-Run resend/reattach/lookup without
further acquisition. LEFT nullability, duplicates and empty schemas pass.

The complete receipt has ten commands with status 0 and complete output,
no evidence errors, clean source identity and five digests matching its
normal producer manifest. Successful temporary installations were removed
after capture; the artifact directory is absent and original receipts/logs
remain. All five tarball digests also equal those recorded for the previous
LIMIT-prefix packed source above: this supplement adds tests/fixtures, not
another product implementation. It does not relabel the old receipt as a
new-SHA execution. The final evidence commit changes only this document.

Full Core, full packed campaigns, Wasm/Native execution and submitted-HEAD
required CI remain unverified for this PR; no manual CI rerun was requested.


## Additional caller: SELECT-window over JOIN without QUALIFY

The same main `040eed2b1a11a3d1f7bae81b68d956d1017fac05` rejects
`SELECT l.x AS x, ROW_NUMBER() OVER (ORDER BY l.y) AS pos FROM t AS l
JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 ORDER BY pos` in lowering
with UnsupportedJoin. The equivalent Pipe script also fails lowering; that
first probe does not identify its specific issue. An independently authored
common JOIN/analytic/projection/sort Program passes the ordinary checker.
The main selection is 1/3 (`run-U1dEy3`, `focused-test-TMawz2`).
This establishes a source-lowering gap, not a publicly executed failed Run.

An attempted diagnostic using generic Debug for Issue failed compilation
(`run-GFPamD`, `focused-test-I3iT3g`, no executed tests); the public Issue
has no Debug implementation. That attempt does not change product code or
establish any rejection category. The existing #1163 repair passes the same
three-case selection (`run-FqsEh0`, `focused-test-H5zG9a`) without another
product change: Analytic before SELECT is a current-row prefix.

`join_select_window_test.mbt` adds a complete, independently written lowering
expectation in addition to the common JSON control. It keeps the JOIN key and
ceiling, input y window order, evaluated pos sort slot and final x/pos column
order. It also checks filter/window expression and LEFT JOIN callers, with
exact UnknownColumn refusals for sibling SELECT aliases and projected-away
input ranges in both query and script compilation.

Final focused checks before packed execution:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_select_window_test.mbt \
  src/query_program/join_order_window_test.mbt \
  src/query_program/join_current_row_prefix_test.mbt \
  src/query_program/window_scalar_projection_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/order-window-source-input.test.mjs
```

JS: 25/25 (`run-hte5AM`, `focused-test-velU8S`). Node: 4/4
(`run-VIOhlw`, `focused-test-qvMoD3`). The earlier 18/18 caller selection
also passed (`run-C3gRD3`, `focused-test-0HrNgj`).

The existing order-window corpus adds eight positives and two exact-code
refusals, for 33 positives / 10 refusals per transport. Handwritten JSON and
SQL/Pipe counterparts expect id/pos rows `(5,5),(1,4),(3,3),(4,2),(2,1)`.
Filter-before-numbering, a scalar parameter expression, nullable unmatched
LEFT rows, typed empty input and repeated id=2 distinguish incorrect operator
placement, dropped arguments, NULL changes and accidental deduplication.
All cases are in the normal corpus as well as the existing narrow consumer.

At this source commit, public execution of the expanded SELECT-window cohort
is pending. Prior prefix and ORDER-window packed receipts above retain their
actual source SHAs; they are not new-SHA acceptance evidence.


### SELECT-window successful public acceptance

Clean packed source: `7cdcaa3b943643718d5461f7318f64db62fa888c`.
The source addition consists of tests, fixtures and this report; the existing
product repair is unchanged. The serial 1200-second guard ran:

```sh
node scripts/packed-client-packages.mjs \
  /private/tmp/actql-b-join-select-window-7cdcaa3b9-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-select-window-7cdcaa3b9-pack \
  node scripts/test-packed-public-query.mjs --order-window-only
```

Guard: `_build/local-checks/attempts/run-H7YXwA`. Original receipt/logs:
`../.codex-scratch/public-query-evidence-2ADgSc`, especially `summary.json`
and `010.stdout.log`. All ten receipt commands returned 0 with complete
output; source is clean and matches the producer revision; evidenceErrors is
empty. Each transport completes 33 positives and 10 refusals. Six refusals
assert exact public codes, including both new SELECT-window scope refusals;
four retained cases assert the existing accepted input-error categories.
The completion marker follows the entire refusal loop for both transports.

The common public harness compares Named Result rows and describe columns
(full contract/nullability/declaration order), including empty results. It
checks one acquisition session, same-Run resend/reattach/lookup without extra
admission or acquisition, and zero Run admission/Source I/O on preparation
refusal. Window/private JOIN columns are absent from the expected public rows
and description. No generated Program is changed by the test application.

All five receipt digests match the normal producer manifest and independently
hashed tarballs. They equal the older ORDER-window digests above because no
product/runtime source changes. This does not relabel the older executions:
this receipt belongs to `7cdcaa3b943643718d5461f7318f64db62fa888c`.
The successful temporary installation has been removed and its directory is
absent. Original logs/receipt and the producer tarballs remain available.

The final evidence-recording commit changes only this report. Its exact SHA,
content review and workflow observation are recorded separately in the PR.
No full Core, Wasm/Native execution, full packed campaign, manual CI rerun or
merge has been performed for this supplement.
