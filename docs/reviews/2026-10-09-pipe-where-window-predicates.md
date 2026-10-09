# Pipe WHERE: predicate-owned window inputs

Date: 2026-10-09. Status: implemented Frontend connection; focused checks and
fresh packed Local/HTTPS acceptance passed. Submitted-HEAD CI remains unverified.

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

Submitted-HEAD required CI, three-target runtime coverage,
full Core, full packed, performance and live Google differential validation are
not claimed by the focused checks above. This unit does not establish complete
SQL/Pipe Frontend coverage.


## Fresh packed public execution

Tested clean product/fixture SHA: `e0b4a5c4db515427658362f6ea03f6c1ed41a291`.
The bounded shared-lock wrapper ran the normal producer, independently verified
its revision and all original tarball digests, then ran the existing focused
window-scalar cohort. No adapter overlay, old pack or product-output oracle was
used. Exact commands, with the repository's pinned Node/MoonBit PATH, were:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-where-window-e0b4a5c4d-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-where-window-e0b4a5c4d-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --window-scalar-only
```

Each Embedded Local/HTTPS entrance completed 49 positives, 28 preparation
refusals and one expected demanded-expression failure. This includes all nine
new positives and six exact-code refusals (five ClientProgramInvalidInput and
one ClientProgramImplementationLimit). Of the complete 28 refusals, 23 have
exact-code log lines; the five older fixtures without expectedCode execute the
existing input-code-set, zero-admission/I/O and submission-lookup assertions
without an individual success log. They are not inferred from log-line count.

The checked app verifies Named Result and stream completion, independent rows,
complete Result.describe types/nullability/column order, no private output
columns, acquisition once and the same Run on resend/attach/reread with unchanged
counters. All preparation refusals preserve zero Run admission and Source I/O.
README Local/HTTPS quickstarts and the deliberate missing-generated-asset
refusal also passed. The existing budget and independent expectations were not
changed to obtain execution success.

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-FULJOU`.
It is passed/complete for the tested SHA; all ten commands have complete output,
exit 0, no signal/error and no evidence errors. Successful external installations
were removed after evidence preservation (`artifactsRemoved:true`). The outer
bounded wrapper completed successfully at `run-AN6Q9L`. Original pack and receipt
remain available; no unrelated scratch or shared dependencies were removed.

| Package | Original tarball SHA-256 |
|---|---|
| client-wire | `4105321db630741cba8d4573d9800f554af51b1b7eff46cdf17f651128ebcc9f` |
| sdk | `e4d0fff729f53b3cd96f97997c2bd052069d2de4152e083d84d4201852b46be6` |
| run-host-core | `b6f1e0f29247268c778e9f3ca57a7e4ec118e1a5369cca6c02c7fc53ce1701db` |
| local-node | `0653ea3adf70fbd44facd5aeb5c462755b16b10f0fe1d4ca086b16a60536d189` |
| node | `aa96b83e047cf3fc42b560b578fc2a32b9a38fa3f32c62dcf9f5eaff26891f4b` |

The subsequent submission commit adds only this English acceptance record. Its
HEAD is not represented as the tested product SHA or as CI success. Parent #1116
remains unmerged; Draft preparation, full required CI and content review remain
separate. JOIN following a nontrivial Pipe prefix is an existing parser coverage
limit; this unit does not claim to support JOIN after a window-owned WHERE.
The broader Frontend goal remains active.
