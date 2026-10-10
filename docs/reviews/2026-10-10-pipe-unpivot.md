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
zero admission/provider I/O on preparation refusals. Public execution is partial:
the final campaign below passes six normal cases on both transports, but stops
at the unchanged SET/RENAME case before refusals.

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
pass their read-only checks. These results do not replace public acceptance.

## Final packed acceptance and common capacity handoff

Clean implementation revision `c6ef8ec98d6d87ac7f739a3e65c88aa8b25c40c3`
produced the normal five packages in
`/private/tmp/actql-b-pipe-unpivot-c6ef8ec98-pack`. The producer manifest records
that exact revision; all five independently checked digests are retained in
`../.codex-scratch/public-query-evidence-a36DI2/summary.json`. There was no
adapter overlay or post-lowering Program edit in this acceptance.

`node scripts/test-packed-public-query.mjs --pipe-unpivot-only` ran under the
existing exclusive bounded wrapper (`run-ij4l2O`). Embedded Local and
authenticated HTTPS each passed six of seven normal cases: both independent
JSON controls, default/exclude/include-with-range source and typed empty input.
For these cases, the ordinary runner verified Named Result rows, descriptions,
type/nullability/column order and repeat-request/read behavior. The last
SET/RENAME case failed on both transports. Its independently expected six rows
and the 512 MiB ceiling are unchanged. The six preparation refusal cases were
not reached. Logs are `010.stdout.log` and `010.stderr.log` next to that summary.
This campaign is failed/incomplete, not successful public UNPIVOT acceptance.

The remaining source is:

```aql
FROM UNNEST(@rows) AS item
|> SELECT item.id AS id, item.jan AS jan, item.feb AS feb
|> SET jan = jan + 100
|> RENAME feb AS february
|> UNPIVOT INCLUDE NULLS(amount FOR month IN (jan,february))
|> ORDER BY id, month
```

Its declarations, three input rows and six expected rows are retained unchanged
in `scripts/fixtures/pipe-unpivot-source-input.mjs`, case
`pipe-unpivot-current-slots-and-labels`. The complete independent machine
control is [pipe-unpivot-current-slots.program.json](fixtures/pipe-unpivot-current-slots.program.json).
The focused lowering test checks the entire ordinary Program against that
authored control, including parameter bounds, SET expression, evaluated slot
rebinding, UNPIVOT arguments, sort and export fields. That selection passes
7/7 (`run-hytw9M` / `focused-test-ZwrGQK`). These new fixture/test changes do
not change the implementation tested in the packed revision above.

Running that independent JSON directly through the standard Embedded Host,
without invoking the frontend, reproduces the same failure as source. The
one-case repository-runtime diagnostic is retained at
`/private/tmp/actql-b-unpivot-diagnostic.test.mjs`; command:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 100 -- /private/tmp/actql-b-unpivot-diagnostic.test.mjs
```

Evidence: `run-6g3xqo` / `focused-test-5kVKYu`, one failed test. The diagnostic
uses Node's debugger only to inspect the caught error and selected capacity;
it does not alter runtime code or successful expected values. Its Store is
`/private/tmp/actql-b-unpivot-diagnostic-store-LqbAr3`. The earlier source
diagnostic (`run-kBZ3Hd` / `focused-test-p4WLqa`) observes the same values.
These diagnostics use the built repository runtime, not a new packed campaign.

Observed root cause:
`LocalManagedStart → Execution → Physical(ExecutionLimit)`. The selected
execution/scratch envelope is **571,311,872 bytes**, retained output is
**14,240,000 bytes**, transfer is zero, and the execution limit is
**536,870,912 bytes**. At rejection, attempts, holdings, held bytes, reserved
retention and reserved execution are all zero. The public
`ACTQL_E_UNPUBLISHED_RUN` is the terminal symptom, not the underlying cause.

The common boundary for A is
`src/connectors/local/selected_relation_provider.mbt`:

- `relation_chain_reclaims_completed_scratch` recognizes binding kernels,
  Groups/CountGroups/AnalyticRows/Unnest, Values and JOIN, but not UNPIVOT.
- `bounded_relation_chain_capacity` therefore sums child execution envelopes
  instead of their sequential maximum. Retained child outputs, metadata handles
  and preparation are included separately.
- The same eligibility decision also controls child cleanup in
  `bounded_relation_chain_execution_state`. The conservative capacity may
  accurately describe the current lifecycle; this evidence does not prove an
  overestimate. Adding UNPIVOT to a whitelist without proving completion
  detachment and cleanup ownership would be unsound.
- `src/connectors/local/driver/managed_dispatch.mbt` passes the selected capacity
  to the existing ledger. `src/physical_resources/ledger.mbt` rejects the
  execution envelope before attempt consumption. No ceiling was raised.

A's required next investigation is the per-child retained/scratch lifetime:
whether UNPIVOT can safely release completed private scratch while retaining
the exact output generation for later sort/export, including cancellation and
cleanup. If the existing bound is necessary, retain the refusal and report
that constraint; do not lower coefficients or alter this fixture's purpose.
B has not edited this common lifecycle/capacity code. The new control and
lowering equality isolate the boundary without inventing a frontend executor.
After a reviewed common fix, B must rerun the unchanged seven normal and six
refusal cases on a newly fixed-SHA normal distribution, on both transports.
Until then PR #1230 remains Draft; full required CI and Wasm/Native execution
are unverified. The wider frontend goal remains active.

## Integration fix: completed UNPIVOT scratch lifetime

The existing bounded UNPIVOT kernel seals its accepted rows into a
completion port capturing only the rows/live references. Its cleanup
clears private mappings, cursors and workspace while preserving accepted
rows. The chain now includes that kernel in the existing sequential
reclamation path. Capacity uses the existing maximum live child scratch
plus every retained child output and metadata/preparation allowance.
Neither the capacity coefficients nor the 512 MiB limit changed.

Three targeted counterexamples failed before the change (run-orMqco).
After the connection, these and existing chain/analytic regressions
passed 14/14 (run-Lm9Ycy): duplicate rows and labels survive cleanup;
false/error cleanup keeps the same child until retry; cancellation
retains reclamation custody without repeated work or source invalidation.
An initial new-test compilation error and a positional-column assertion
were corrected separately; output cells are checked by canonical names.
The fixed public SET/RENAME case still requires fresh packed acceptance.
