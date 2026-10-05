# Grouped scalar IN atoms and shared membership execution

## Shared execution update

The current change integrates main `ded488baccbdd37892fce3a03ac158f33d676348`
and implements `in` and `not_in` in the common typed lowering and execution
owners. Grouped atoms still retain their original parameter/sign normalization;
no equality/OR expansion or Frontend-only execution rule is introduced.

The approved [common membership law](../spec/language.md#membership-semantics)
treats a NULL array and an empty array as the empty set. IN is false and NOT IN
is true on that set, including a NULL left operand. `[NULL]` remains nonempty.
Both operands are evaluated once, including failures on an empty-set query.
The runtime scan uses common exact scalar equality, bounded per-item control
work, full operand logical charges, and the existing temporary-root owner.
A match does not discount later logical work or discard required operands.

Typing excludes container nullability and proves nonnullable Boolean for a
`max_items: 0` collection. The specification, machine law, dependent contract
pins and independent identities change together without a version bump.
Canonical normalization still does not fold away expression demand, failure,
work or identity. SQL `IN ()`, unsupported UNNEST and subqueries are not added.
The historical Frontend baseline bytes remain available unchanged while the
active law-dependent identities use independently recomputed expectations.

Focused JS verification on this source union passed 195 expression-typing
and 226 lowering tests; a 34-test runtime/caller selection; 755 Frontend and
identity tests; 1,145 shared execution and pipeline-identity tests; and four
query-integration pin callers. These selections overlap and are not a summed
suite count. Ninety-one focused Node contract/identity checks pass, including two
complete independent preimages for the law-dependent ordered-node and fragment
fixtures. An intermediate 1,141/1,145 run exposed four stale fixed CIDs; their
explicit preimages were independently rebuilt before the successful rerun.

The first fresh candidate executed all seven original positive Local cases,
then rejected an added JSON control because its authoring helper emitted an
empty `params` object. The helper now omits absent declarations; an independent
fixture guard and installed ordinary preparation check cover that correction.
The failed candidate remains distinct from successful final acceptance.

The ordinary public corpus contains 17 positive and seven refusal cases,
including direct false/true/NULL SELECT results in JSON, SQL and Pipe, NULL-item
match precedence, and supported JSON empty/NULL-array boundaries. Fresh packed
Local/HTTPS results, exact source SHA and package digests are reported on
[PR #435](https://github.com/actql/actql/pull/435). Focused JS and Node checks do
not establish complete Core, Wasm/native, full packed-corpus or CI success.

## Historical frontend-only evidence

The rest of this report records the earlier frontend-only revision and its
then-missing common execution dependency. Those failure results are retained
as historical evidence, not the current implementation status.

## Fixed source and completion boundary

- Base: `e7944647657f93bd20f5f95d19e8d5f6f764bde2`, latest available main
  when this independent worktree was integrated. Includes #421, #423 and #426.
- Product and acceptance-fixture commit:
  `5130b81859c54c2ebd699788c54e85a22302a113`.
- Branch: `fix/frontend-grouped-in-atoms`; target: main; Draft until the
  common IN implementation and positive packed acceptance are available.
- Changes are in query expression lowering, caller fixtures and the existing
  packed public-query harness. No common Owner, CTE, Effect, provider, wire,
  authorization or budget implementation is changed.

The shared syntax corpus already normalizes `x IN ((1), (($p)), -(2))` to
the common `in` node with an immediate scalar parameter hole and a numeric
literal (`src/expression_syntax/corpus.generated_wbtest.mbt`). The query
frontend previously recognized only an immediate `ParameterReference` or an
immediate numeric child of unary signs. Grouping erased that classification:

```sql
SELECT id FROM orders WHERE amount IN ((@p), -(2)) ORDER BY id
```

The independent full Values Program passes the ordinary checker with `p=1`,
but this source fails before checking at the original main baseline. The
new postorder atom metadata retains grouping, numeric validation and parameter
identity without reparsing, expanding an IN list into comparisons, or admitting
dynamic list expressions. `IN ((amount))`, `IN ((1+2))` and `IN (-(@p))`
remain unsupported in this implemented profile. Those are coverage limits,
not claims that GoogleSQL prohibits these forms.

The independent NULL expectations follow the selected
[GoogleSQL IN operator rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#in_operator):
a matching value wins over NULL, otherwise a NULL equality yields NULL;
NOT IN negates that result. Parentheses do not change the scalar value.
No live differential run against a Google service was performed.

## Focused verification

Used the pinned MoonBit toolchain and `scripts/local-checks.mjs` with the
existing bounded, nonzero-test guard. No full Core or cross-target run.

| Selection, JS | Before fix | After fix | Evidence attempt |
|---|---|---|---|
| `src/query_program/grouped_in_atoms_test.mbt` | 1/2; independent Program checked, source failed | 2/2 | `run-He8P0b`, `run-4mJMVO` |
| `src/query_expression/grouped_in_atoms_test.mbt` | 0/3 | included below | `run-m0H1eO` |
| `src/query_expression` | not run as a baseline package | 13/13 | `run-A31IhL` |
| `src/query_program/compile_test.mbt --filter '*declared query parameters*'` | existing regression | 1/1 | `run-OHXCwt` |

Commands have the form
`node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js <selection>`.
The initial caller test had a test-helper type typo (`Value` instead of
`Cursor`), corrected before the semantic baseline; that compilation failure
is not the product counterexample. Changed MoonBit files were formatted;
the three changed Node scripts passed `node --check`, and `git diff --check`
passed. Typed expression refusals cover dynamic items, negative zero,
out-of-domain numbers, and the existing work limit.

## Packed evidence: executed and not executed

Clean commit `5130b81859c54c2ebd699788c54e85a22302a113` was normally packed
with prepack enabled, installed outside the checkout, and executed without a
MoonBit toolchain in the runtime PATH:

```sh
node scripts/test-packed-public-query.mjs --grouped-in-only --keep-artifacts
```

The command ran under the existing serial heavy guard with a 720-second
budget. `--grouped-in-only` selects the changed cases; they are also registered
in the ordinary packed corpus. Each command retains source cleanliness, SHA,
stdout/stderr, exit status and package digests.

Producer evidence: `public-query-evidence-veUTQH`, guard `run-SW6rvM`.
All five packs, clean installation, package-boundary checks and README
Local/HTTPS rows succeeded. The first positive IN JSON control failed;
none of the seven positive IN execution cases completed. This run is failed,
not an acceptance success, and did not reach positive HTTPS execution.

| Tarball | SHA-256 |
|---|---|
| client-wire | `9dddd809931f810598bf6669ffd211b716c40bd34b9f169073b90d11cc014595` |
| sdk | `440cc4585c66840867f645708c6654435e7f111dc119f91f3bd4ccf117a11207` |
| run-host-core | `cdacf102e0615594dd7aafeb45612786f59235b900884ae40860eb71f48b9c99` |
| local-node | `f123d084f6dba9d4d88ccfaa7affd05ce971a3093a77a99bd8af2225318c584e` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Retained-package diagnostics checked those digests and the producer's clean
source SHA, then copied the same installed bytes into separate private roots
without rebuilding. `public-query-evidence-60rI1k` / `run-hhWMoB` adds only
private error logging to `publicClientErrorCode`, restores its original bytes,
and reproduces the JSON failure. It is an overlaid failure diagnostic.

`public-query-evidence-FADhZ4` / `run-qHidGA` uses unchanged libraries:

- Formal SQL, Pipe and independent JSON preparation succeeds in the real
  installed environment with the published alias table and parameter value.
- All three task-compilation calls reject with the same common issue below.
- A disclosed selection excludes all seven unresolved positive executions,
  then runs six preparation refusals through public Local and HTTPS: undeclared
  parameter, missing value, wrong type, dynamic column, dynamic arithmetic,
  negative zero. All six pass in each mode, including Run admission zero,
  provider I/O zero and request lookup not found. Public check also passes.
- The harness's generic acceptance banners refer only to that refusal
  selection. They do not establish positive IN execution, rows, descriptions,
  Source acquisition counts, or resend behavior.

Evidence roots are the named directories under the local
`worktrees/.codex-scratch`; guard evidence is beneath this worktree's
`_build/local-checks/attempts`. Logs, original tarballs and failed Stores are
retained. No test-side Program repair or executor was used.

## Common Owner handoff: IN is checked but not lowered for execution

The public JSON call reports `SubmissionUnknown`, caused by a definite
`ClientHostFailure` / `RunHostTaskCompilationRejected`. That public code is a
terminal symptom; it does not identify the common missing operation.

The formal APIs used with the same installed environment are:

1. `clientProgramPrepareSourceWithParameters` (SQL/Pipe), or
   `clientProgramPrepareEffectFreeWithParameters` (independent JSON).
2. `clientProgramPreparationReady`: returns a prepared checked owner.
3. `clientProgramSemanticDocumentJson`: emits the unchanged Program.
4. `clientProgramCompileLocalTasks`: rejects while preparing a task fragment.

The decoded failure chain is:

```text
ClientProgramTaskCompilationBridgeIssue.Compilation
  ClientTaskCompilationIssue.Plan
    ClientValuesExecutablePlanIssue.TaskGraph
      ClientTaskPlanGraphIssue.Fragment
        ClientTaskFragmentIssue.Pipeline
          ClientTaskPipelineIssue.Sequence
            SequenceIssue.KernelFailure(step=0)
              KernelIssue.ExpressionFailure
                ExpressionNotImplemented("in")
```

`src/lowering_relation/expression.mbt::expression_tag` has no `in` or
`not_in` branch or matching execution expression body. This source evidence
agrees with the installed typed rejection (`ExpressionIssueKind` tag 7,
payload `in`). This is a common expression/IR/Owner connection for A,
not another frontend name-resolution fix. B has not changed it or worked
around it by duplicating comparisons, moving filters, weakening checks or
depending on provider-specific pushdown. Public error classification can be
handled by its existing Owner; this PR does not change it.

Reproduction inputs and independent expectations:

- [Authored JSON control](fixtures/grouped-in-expected.program.json).
- [Source rows and parameter value](fixtures/grouped-in-input.json).
- [Independent expected rows and ordered column contract](fixtures/grouped-in-expected.rows.json).
- [Actual emitted SQL Program](fixtures/grouped-in-generated.repro.program.json):
  reproduction only, never an expected-value oracle. The source pushes its
  predicate into the existing capture stage; the independent control keeps
  it on the consumer. Both reject the same IN expression when compiling.
- [Public source cases](../../scripts/fixtures/grouped-in-source-input.mjs).
- [Full independent Values Program and checker fixture](../../src/query_program/grouped_in_atoms_test.mbt).

A can reproduce against the normal package source SHA above and the ordinary
Client entry with `parameters: {p:3}`. Expected ordered output is
`[{"id":-2},{"id":3},{"id":3}]`, one Source acquisition, and no additional
acquisition or acceptance on identical request resend. Additional independent
fixtures preserve IN/NOT IN NULL results, nullable parameter values, empty
input, column order and full type contracts.

Resume all seven positive Local/HTTPS cases using A's accepted common fix and
a fresh fixed-SHA pack. Until then, typed refusal success and correct Program
lowering are separate from positive public execution. CI, Wasm/native and the
complete packed corpus have not been verified for this branch.
