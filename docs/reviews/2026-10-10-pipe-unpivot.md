# Pipe UNPIVOT connection

## Baseline and missing boundary

The branch starts from main `749d6e4b6e49b51381cac9c77f96cece1f5e1e56`.
The adopted GoogleSQL reference is
`d82db99a923a46571f543a13899dc791a7b6f743`; its `docs/query-syntax.md`
UNPIVOT rules and `docs/pipe-syntax.md` UNPIVOT entry define NULL exclusion,
unqualified source columns, generated labels and output column order. Its
`googlesql/analyzer/testdata/pipe_unpivot.test` confirms the fresh result range.
This is selected-profile implementation evidence, not full GoogleSQL conformance.

The independent normal Program in `src/query_program/pipe_unpivot_test.mbt`
already passes the ordinary checker. Before the patch, the matching source
`FROM pair |> UNPIVOT INCLUDE NULLS (amount FOR column_name IN (x,y))`
fails parsing. The focused pre-fix run executed two tests: the JSON control
passed and the text connection failed. Evidence:
`_build/local-checks/attempts/run-ZrCaZb` and
`_build/focused-evidence/focused-test-qwUay5`.
The two independently known rows are `{amount:7,column_name:"x"}` and
`{amount:9,column_name:"y"}`; no product output generated those expectations.

## Connection and ownership

The parser retains a single-value UNPIVOT clause. A new lowering helper copies
current evaluated fields into uniquely named internal fields, calls common
`unpivot`, and translates its physical field labels to resolved public column
names. Default/explicit EXCLUDE NULLS adds an ordinary `IS NOT NULL` filter.
The public scope contains unmentioned fields in input order, followed by value
and name columns. Prior ranges and consumed columns cannot be revived.
The existing Pipe JOIN input classifier recognizes this fresh projected scope.

No checker, executor, evidence derivation, resource ceiling, Source acquisition,
Result order owner or persistence boundary is added. This branch does not edit
the CTE predicate, assertion or Effect owners. The common UNPIVOT checker still
owns exact type/nullability validation and expansion/key evidence.

This first connection leaves FROM-suffix syntax, multi-value-column forms and
row-value aliases unimplemented. The common exact-nullability requirement also
differs from the broader selected reference and remains a recorded contract gap.
Those cases are not approximated, silently coerced or declared permanent
language restrictions. PIVOT remains a separate unconnected operation.

## Independent and public acceptance

`src/query_program/pipe_unpivot_test.mbt` contains a complete independently
authored generated Program, a simpler checked JSON control, default filtering,
SET/RENAME slot preservation and exact scope/name refusals. The focused JS
selection includes the directly affected existing Pipe scope/JOIN tests.
After the connection, 17/17 tests passed:
`_build/local-checks/attempts/run-AqRgJs` and
`_build/focused-evidence/focused-test-a6Xf1L`.

The public fixture has seven normal cases and six preparation refusals. Its
independent JSON controls and source cases retain duplicates, SQL NULL,
nullable empty schemas, changed current slots, labels and declared field order.
Both full public registration and `--pipe-unpivot-only` use those same cases.
The normal runner checks Named Result rows and descriptions, resend/reread and
zero admission/provider I/O on preparation refusals. These public executions
are not yet claimed successful by this record.

The changed query grammar/rules change the grammar-bound Run identity.
The independent vector retains the complete preceding grammar/Run preimages
in `scripts/fixtures/pre-pipe-unpivot-grammar.json`; current identities are
reconstructed from authored preimages, not runtime CID output. Program, Values
Unit, Result Plan, existing common UNPIVOT meaning and barrier contracts are
unchanged. Generated manifests/metadata/identity tests use their existing
generators. A new grammar pin does not rebind an old saved Run.

## Remaining validation

Executed focused checks (pinned Node/MoonBit, JS backend):

- `node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js src/query_syntax/unpivot_test.mbt src/query_program/pipe_unpivot_test.mbt src/query_program/pipe_scope_test.mbt src/query_syntax/pipe_join_input_test.mbt`: 17/17.
- The UNPIVOT syntax/lowering plus `src/run_publication_host/client_values_run_materials_wbtest.mbt` selection after manifest regeneration: 11/11, evidence `run-MoacSx` / `focused-test-jK9lLD`.
- `node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/pipe-unpivot-source-input.test.mjs scripts/public-query-profiles.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs`: 40/40, evidence `run-y6T47E` / `focused-test-LIAL9O`.
- `scripts/frontend-profile.test.mjs` after recording implemented Pipe coverage as partial: 9/9, evidence `run-yMrxi3` / `focused-test-qzKG0x`. No runtime evidence was added to the design profile.
- Read-only compilation manifest/document metadata/spec-family/canonical checks: clean; 384 canonical identities. `moon info src/query_syntax` generated the changed interface. `git diff --check`: clean.

Normal clean-HEAD five-package production and packed Local/authenticated HTTPS
must complete before this unit can claim public execution. Full Core,
Wasm/Native execution, full packed campaigns and submitted-HEAD CI are not
claimed by the focused checks. The wider frontend migration remains incomplete.
