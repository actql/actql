# Pipe SET: inline window assignment inputs

Date: 2026-10-09. Status: implemented Frontend connection; focused checks passed.
Fresh packed Local/HTTPS acceptance and submitted-HEAD CI are not yet established.

## Counterexample and selected meaning

Adopted main: `ffe46cdae6d064a60da517dec2937eeaee4a1c30` (fetch reconfirmed).
Parent #1121 remains unmerged at `1da668809bb5ba9b65b442e259de2f682d5cfabe`,
following #1116/#1115/#1111. Final target is main; this unit does not change a
shared execution owner, D's CTE/Effect processing or another worktree.

The [GoogleSQL Pipe SET](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#set)
replaces existing current columns while range variables retain original values.
The same reference's order-preservation section explicitly distinguishes SET
using window functions. The selected inline window profile belongs in ordinary
SET expressions, without a new inference, analytic or assignment executor.

```aql
FROM t
|> SET x = ROW_NUMBER() OVER (ORDER BY y)
|> ORDER BY x
```

For input `(x,y) = (1,20),(2,10)`, expected public rows are
`{x:1,y:10},{x:2,y:20}`. Both columns remain in order and non-NULL. The independent
ordinary Analytic/Derive/Sort/Select control passes the checker; baseline
`run-uRpD4n` / `focused-test-t1oIVY` records 1 passed, 2 source parsing failures.

The complete expected Program is independently authored. Its private assignment
slot follows the existing allocator rule: start at the number of retained
physical fields, not at zero. Two input fields plus one private analytic field
mean `aql_pipe_set_3`. Initial connection `run-0vxKzE` (19/20) exposed that
internal-name mistake in the new test; correcting it preserved every operation,
reference, row, type, order and limit. No expected public result was changed.

## Connection and retained boundaries

The parser extracts direct or embedded window calls through the existing
bounded window-expression callback, collecting sibling calls before SET. The
existing window resolver supplies ordinary AnalyticExpressions; ordinary GROUP
calls cannot be introduced in assignments. Prior SELECT/EXTEND WINDOW names do
not leak. This unit connects inline specifications, not a SET WINDOW declaration.

`compile_steps` passes the evaluated private analytic bindings alongside the
pre-SET current-row snapshot and immutable ranges to the existing expression
lowerer. All sibling assignments read that snapshot, then normal replacement
slots change only current columns. Target existence/duplication checks remain.
Private bindings are cleared afterward; normal final projection exports only
current columns. The common checker determines new types and nullability.
Authored placeholder-like names cannot be captured.

Parameters, predicates, analytic signatures/frames, expression demand, capacity,
Result order and capture ownership are unchanged. No Source predicate or limit
is rewritten. Explicit final ORDER BY is used in public controls. JOIN after a
nontrivial Pipe prefix remains a separate existing coverage limit.

## Independent fixtures

The normal/focused window-scalar corpus gains nine positives and eight exact-code
preparation refusals. Independent JSON and text controls use the same rows/types:

- Direct replacement and a scalar operand preserve visible column order.
- Typed parameter values use the existing declaration/value path.
- Empty input retains the replacement's complete describe schema.
- LAG preserves nullable replacement values without restoring the old type.
- Sibling replacement of id reads old nullable amount, not its new row number.
- An original range still reads the displaced amount after window assignment.
- An authored placeholder-like name is a real input and retains NULL propagation.
- Missing/duplicate targets, missing/projected-away input, replaced range,
  private-slot reference and leaked WINDOW name are invalid input; missing
  aggregate frame remains the existing implementation-limit refusal.

The shared acceptance app compares independent Named Result rows, stream
completion, describe type/nullability/column order, no internal fields,
acquisition once, same-request Run identity and unchanged counters after
attach/resend/reread. Refusals require zero Run admission and Source I/O.
No generated Program is repaired by the test before submission.

## Identity and generation

Grammar changes
`sha256:e0ad6a5fa648e290e490096887361d02e7a9b223c1d6a267646c6974a874d832`
→ `sha256:c4364e9947c8d6c7538d9245fca2da3fc0cd44bd70caceff58862ba9629c90d6`.
Independent fixed Values Run changes
`sha256:f0fc9b3b44633c03def0118d8d40e4d34068720763fa744e1d161f57541839a5`
→ `sha256:71a90eff92faeb07d1efe6c8bbe56bdcaac3d87a04b6a6c2f3e314a52503e069`.
Program, expression, Unit, proof and ResultPlan contracts are unchanged. The
complete previous grammar and independently reconstructed Run preimages are
retained in `scripts/fixtures/pre-pipe-set-window-grammar.json`. Existing canonical
Values oracles determine consumer expectations; no runtime-issued CID is copied.
Historical saved Runs are not rebound to new grammar or current dependencies.

The four existing compilation-manifest, document-metadata, spec-family and
canonical-identity generators update their owned outputs, separate from
independent fixture authorship.

## Focused evidence and remaining coverage

- Baseline common control: 1/3; both source examples rejected (`run-uRpD4n`).
- Expanded SET/scope/WHERE/EXTEND callers: 24/24 (`run-nMX69w`,
  `focused-test-9zxdld`).
- Final pinned JS plus consuming Values identity: 25/25 (`run-fTN5os`,
  `focused-test-eVxIRL`). Exact refusal reasons are asserted.
- Fixture, independent grammar/Run vectors and manifest tests: 23/23
  (`run-5N2K7c`, `focused-test-nuHCnP`).

- Public fixture/document/import checks: 22/22 (`run-MbZ2dU`,
  `focused-test-gjKYIE`). All four read-only generator checks pass;
  382 canonical identities match and metadata needs no writes.

Fresh normal five-package production and focused packed Local/HTTPS acceptance
remain to be executed. Submitted-HEAD required CI, three-target runtime coverage,
full Core/full packed/performance and live Google differential validation are
unverified. Draft preparation is not merge CI. The broader Frontend goal remains
active; this connection is not complete standard analytic coverage.
