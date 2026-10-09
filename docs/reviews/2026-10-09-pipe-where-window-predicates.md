# Pipe WHERE: predicate-owned window inputs

Date: 2026-10-09. Status: implemented Frontend connection; focused checks passed.
Fresh packed acceptance and submitted-HEAD CI are not yet established.

## Boundary and counterexample

Adopted main is `ffe46cdae6d064a60da517dec2937eeaee4a1c30`. This unit follows
named Pipe SELECT parent #1116 at `a85b000efc1474b6f5d013754df5eccae63ef988`;
its final integration target is main. No shared execution owner is changed.

The selected [GoogleSQL Pipe WHERE](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#where)
allows window functions in its predicate, replacing QUALIFY in a Pipe query.
An independent ordinary analytic/filter Program already passed the common
checker, while these equivalent source entries were rejected by the parser:

```aql
FROM t
|> WHERE ROW_NUMBER() OVER (ORDER BY y) <= 1
|> ORDER BY x
```

For input `(x,y) = (1,20),(2,10)`, the independently expected public row is
`{x:2,y:10}`. The output retains both current columns; the predicate's row number
must not be a public field. Baseline `run-sr2wn8` / `focused-test-Ie4YO9`
recorded 1 passed and 2 failed: the common control passed, source parsing failed.
The complete expected Program in `pipe_where_window_test.mbt` is authored
independently, not generated from compiler output.

## Connection and scope

The Pipe WHERE parser now uses the existing bounded window-expression callback
and named-window resolver. Ordinary aggregate calls cannot introduce implicit
GROUP here; prior AGGREGATE outputs are ordinary current columns. SQL WHERE
remains unchanged. WHERE does not inherit previous SELECT/EXTEND declarations.

`compile_steps` passes only the predicate's evaluated private analytic bindings
alongside the current columns and immutable ranges to the existing expression
lowerer. After filtering it clears those analytic bindings. The normal final
current-row projection removes private fields before publication. Sequential
WHERE windows observe the surviving current rows. NULL predicates are excluded
by the common filter contract. No Source predicate, parameter, frame, capacity,
Result order, execution owner or capture boundary is rewritten or relaxed.

## Independent public fixtures

The normal and focused window-scalar cohort gains nine positives and six
preparation refusals, including an independently authored JSON Program control:

- Direct top-three filtering preserves ordered nullable `amount`, then `id`.
- Typed parameter top-two filtering preserves the declared value path.
- Empty input retains the same describe contract.
- Nullable LAG excludes NULL predicates while preserving retained NULL values.
- Two windows in one predicate and sequential predicates have distinct controls.
- SET changes current columns while the original range keeps its input values.
- An authored name resembling a private placeholder is not captured.
- Missing/projected-away columns, private-slot references, replaced range aliases
  and leaked WINDOW names are typed invalid input; an unsupported aggregate frame
  remains the existing implementation-limit refusal.

The existing acceptance app checks independent rows, complete describe columns,
NULL/type/column order, no unexpected fields, capture counts, same-request Run
identity and Result rereads. Preparation refusals require zero Run admissions
and provider I/O. No test repairs the generated Program after lowering.

## Identity and generation

The query grammar manifest changes from
`sha256:621f06cc9ffc651a0d68da0b7994163bef2439b4b72a8608ccc480622e4c67d9`
to `sha256:e0ad6a5fa648e290e490096887361d02e7a9b223c1d6a267646c6974a874d832`.
The independent fixed Values Run changes from
`sha256:02061c277b626444a02a26037851c14b49ea2fd7064a423eab92f17e3bc33799`
to `sha256:f0fc9b3b44633c03def0118d8d40e4d34068720763fa744e1d161f57541839a5`.
Its Unit, proof, Result Plan, Program and expression contracts are unchanged.
The complete previous grammar and independently reconstructed Run preimages are
retained in `scripts/fixtures/pre-pipe-where-window-grammar.json`; historical
Runs are not rebound to new grammar. Consumer expectations use independent
canonical preimages and the existing normative Values oracles, not product CIDs.

The existing compilation-manifest, document-metadata, spec-family and canonical
identity generators update their owned outputs. Independent fixtures are not
regenerated from compiler or runtime output.

## Focused evidence and remaining work

- New exact-reason tests: 6/6 (`run-5Po3al`, `focused-test-vwNpAb`).
- Final selected JS callers and Values identity: 42/42 (`run-NTdg19`,
  `focused-test-g1kQwd`).
- Fixture and independent grammar/Run vectors: 16/16 (`run-NOMCCG`,
  `focused-test-4sfA9D`).
- Public fixture/document/manifest checks: 24/24 (`run-lSLKjI`,
  `focused-test-ofwKkM`). The attempted selection named `import-metadata.test.mjs`,
  which is not a test file at this revision and was not executed; actual
  spec-family import coverage is recorded separately below.
- Actual spec-family import checks: 3/3 (`run-qG61Yk`,
  `focused-test-7LHSRK`).
- All four read-only generator checks passed; 382 canonical identities match
  and document metadata needs no writes.
- Earlier connection/caller probes passed 28/28 and then 31/31. A malformed
  tuple in the expanded refusal test caused a compilation-only fixture failure
  (`run-jZZ3O2`); it was corrected without product changes. A subsequent 5/6
  result (`run-dCAVRb`) guessed UnsupportedOrdering where the current scoped
  expression lowerer correctly returns UnknownReference. The final test now
  fixes that exact refusal rather than accepting any error.

Fresh normal five-package production and focused Local/HTTPS public acceptance
remain to be executed. Submitted-HEAD required CI, three-target runtime coverage,
full Core, full packed, performance and live Google differential validation are
not claimed by the focused checks above. This unit does not establish complete
SQL/Pipe Frontend coverage.
