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

The parser retains a single-value UNPIVOT clause. The lowering helper reuses
current evaluated fields and calls common `unpivot`. When a selected field has
a private or renamed slot, one ordinary SELECT first binds evaluated values to
their current public column names. Common UNPIVOT then generates the correct
labels directly, without a second per-row string value. Fresh generated fields
avoid collisions with kept fields; unchanged names require no copy projection. Default/explicit EXCLUDE NULLS adds an ordinary `IS NOT NULL` filter.
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
After the initial connection, 17/17 tests passed:
`_build/local-checks/attempts/run-AqRgJs` and
`_build/focused-evidence/focused-test-a6Xf1L`.

The public fixture has seven normal cases and six preparation refusals. Its
independent JSON controls and source cases retain duplicates, SQL NULL,
nullable empty schemas, changed current slots, labels and declared field order.
Both full public registration and `--pipe-unpivot-only` use those same cases.
The normal runner checks Named Result rows and descriptions, resend/reread and
zero admission/provider I/O on preparation refusals. The public source executions
are not yet claimed successful by this record. See the failure boundary below.

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

## Initial public failure and focused correction

Clean revision `56a12d9f9ac68c37cdd2940761b749523d363f66` produced all five
normal packages in `/private/tmp/actql-b-pipe-unpivot-56a12d9f9-pack`; its
manifest revision and all five tarball SHA-256 digests were independently
verified. The scoped public run (`run-7xdf7R`) passed both independent JSON
controls on Local and authenticated HTTPS. The first source case,
`pipe-unpivot-default`, then failed after admission. The remaining source and
refusal cases were not reached. Public evidence is retained in
`../.codex-scratch/public-query-evidence-ChaAfs/summary.json` (relative to this
worktree's parent directory), with `010.stdout.log` / `010.stderr.log`.

The terminal `ACTQL_E_UNPUBLISHED_RUN` is not the root cause. A single-case
standard-Host diagnostic observed
`NodeHostFailure.LocalManagedStart(LocalDispatchIssue.Execution(RunIssue.Physical(ExecutionLimit)))`.
Evidence: `run-gsBppD` / `focused-test-szVSrb`. These repository-runtime
diagnostics are not fresh-packed execution evidence. No common Owner was
modified; Node's debugger inspected the caught exception without changing
product code. The diagnostic Stores remain in `/private/tmp/actql-b-unpivot-diagnostic-store-*`
and must not be treated as disposable successful acceptance environments.

The initial lowering copied every current field to fresh slots, then derived
labels to undo that copying. A diagnostic JSON Program removing those two
redundant operations succeeded with the same standard Host and unchanged
limits, returning the independently expected three rows. Evidence:
`run-MUyg16` / `focused-test-B6Mz4D`. That hand-edited diagnostic is not a
source acceptance substitute. The lowerer first reused already evaluated input slots, but a second diagnostic
(`run-MN8ti9` / `focused-test-ofcyGT`) showed that the SET/RENAME label-derived
string column still exceeded the same execution limit. The final lowering uses
one ordinary SELECT only for a real logical / physical name difference; it
reuses evaluated values under their current column names and lets UNPIVOT
generate labels directly. No label-translation expression is emitted. The independently authored
complete Program expectation was revised for this minimal lowering; expected
rows, NULLs, multiplicity, sort and resource limits are unchanged.

A new parameter-array regression checks the normal checker and absence of
redundant copy / label slots in the unchanged default source. The focused
parser/lowerer/scope/JOIN selection now passes 18/18:
`run-OT9QIj` / `focused-test-e5ymmB`. Fresh normal five-package production and
source-to-Named-Result Local / HTTPS acceptance after this correction remain
required; the diagnostic JSON success does not satisfy that obligation.

## Main integration and final focused selection

Main `4634a65cb625596391d611159deab0de09cd93cd` was normally merged. Its
BETWEEN, Graph rows JOIN, traversal JOIN and semantic refusal cases remain
registered alongside this branch's seven normal and six refusal cases. Four
conflicts were limited to the packed selection flags and independent authored
inventory / count assertions; no common Owner or workflow was replaced.
The data-only inventory enumerator now records 3,226 cases (2,041 successes,
1,139 refusals, 46 execution failures). This is registration coverage, not
execution coverage.

The integrated Node selection passes 53/53 (`run-kwNpKz` /
`focused-test-2Jn72s`). The final evaluated-slot/rebinding implementation passes
18/18 focused JS tests (`run-OwlaEv` / `focused-test-Tn72HZ`). Compilation
manifest, normative metadata, spec-family and all 384 canonical identities
pass their read-only checks. These results still do not replace the pending
fresh-packed source acceptance.
