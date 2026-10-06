# Analytic output aliases preserve SELECT input scope

Baseline: `00c7687d98c28e8c733c45d8a12bcb435ff9cd67`.
This closes an existing frontend implementation defect, without adding syntax,
changing common numerical/analytic contracts or editing execution/Host owners.

## Contract and executed counterexamples

The existing query contract says SELECT siblings and WHERE see the input
snapshot; ORDER BY gives SELECT aliases precedence, while qualified input
references keep their source meaning. Google's [alias visibility and ORDER BY
rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#using_aliases)
support that distinction. `OVER` also resolves against the input snapshot.

Three independently authored tests failed on the baseline (`run-5juJtk`, 0/3):

- `SELECT id, ROW_NUMBER() OVER (ORDER BY amount DESC, id) AS amount FROM orders`
  rejected an alias that shadows a real input column. Its complete independent
  ordinary Program passed the normal checker before source compilation failed.
- `SELECT *, ROW_NUMBER() OVER (ORDER BY amount, id) AS pos FROM orders` rejected
  because analytic output `pos` was already included in star expansion and then
  selected again explicitly.
- `SELECT ROW_NUMBER() OVER (ORDER BY amount, id) AS pos, pos + 1 AS later FROM orders`
  wrongly accepted a reference to a SELECT sibling alias absent from the input.

The failures are frontend compilation/scope evidence, not a claim of an executed
public Run returning incorrect rows. A fourth regression prevents a qualified
input reference from treating an absent input column as an analytic output.

## Minimal repair

`query_program/compile.mbt::compile_steps` keeps the analytic input snapshot and
an explicit authored-alias to evaluated-slot mapping. A collision allocates a
private output slot using the existing allocator and reserved names. Analytic
functions retain their ordinary shared lowering; SELECT projects the evaluated
slot back to the authored name. Noncolliding output names retain their existing
Program shape.

SELECT siblings/star expand only the input snapshot. Scoped Pipe SELECT reads
its existing visible/range mappings, with analytic output handled separately.
ORDER BY input fallback uses the saved input fields; selected alias bindings
continue to reuse evaluated output slots. The temporary mapping is discarded
after SELECT so subsequent Pipe operations see the materialized output scope.
No input alias is revived, expression is expanded for reevaluation, checker is
relaxed, capacity is increased or execution owner duplicated.

This is a lowering-only semantic-preservation fix. Normative grammar/schema/
law bodies and their pins are unchanged. Independent expected Programs are
hand authored, not rewritten from compiler output.

## Focused and public evidence

The repaired tree passed selected JS 34/34 in `run-9IaoWX`:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/analytic_output_scope_test.mbt src/query_program/analytic_order_expression_test.mbt src/query_program/analytic_partition_property_test.mbt src/query_program/grouped_analytic_offset_test.mbt src/query_program/group_select_input_scope_test.mbt src/query_program/pipe_scope_test.mbt
node scripts/local-checks.mjs test node -- scripts/analytic-output-scope-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

Node expectations/profile/corpus checks passed 9/9 in `run-UbHZX4`.
Selected formatting, JavaScript syntax and `git diff --check` passed. These
are implementation-tree results before commit, not hosted CI or packed proof.

The ordinary packed corpus and narrow `--analytic-output-scope-only` selection
share the same authored fixtures. Normal cases include an independent JSON
control, alias/input order reversal, scoped Pipe, star, a later SELECT and empty
typed output. Refusals cover sibling/qualified alias misuse and duplicate output
names. They retain the installed `analytic-order` ceilings, zero admission/I/O
on preparation refusal, Result.describe column/type/nullability assertions,
shared Source counters and same-request replay/attach/reread checks.

Committed-SHA normal packing and Local/HTTPS results will be recorded separately.
Full Core, other targets, all packed/proof/performance and hosted required
coverage are not established by these focused checks. Duplicate public output
names remain subject to the current Result contract; no new renaming policy is
introduced. No merge or manual CI retry is performed.


## Fixed-source public execution

Runtime source: `5fc9c6de046d6ffe39b80bfe1e201c197cbc3f6b`.
The guarded normal producer and narrow public consumer completed successfully
in `run-03grah`:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-analytic-output-scope-pack-zwxhvY
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-analytic-output-scope-pack-zwxhvY node scripts/test-packed-public-query.mjs --analytic-output-scope-only
```

Embedded Local and HTTPS each passed all 7 normal cases and 3 preparation
refusals. The independent JSON control and authored source agree on values,
ordered columns, types and nullability. Alias ordering gives ids `3,4,1,2`;
qualified input ordering gives `1,3,4,2`. Star publishes only input columns
plus the explicitly selected result, with no private output/sort column.
The empty result remains described as a non-nullable number column. Same-ID
resend, attach and reread preserve Run and Source counters; preparation failures
preserve admission and provider I/O zero. No expectation or ceiling changed to
obtain these successes.

Receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-WBrno9/summary.json`
(`passed`, complete, no evidence errors, successful artifacts removed).
Protected local archive: `review-artifacts/b-analytic-output-scope-2026-10-06/`.

| Package | SHA-256 |
| --- | --- |
| client-wire | `68e1aa6b3539f5833630693a5a10e084f61a2ab7f4e2e4f978722a33ce6e9e90` |
| sdk | `a17d3678138d9e6c41625f26e279811f7d264fdc7f7653be71877abffec25a36` |
| run-host-core | `570d18449a1aa46afe9215ed174ffefe716fe0d042190188d6572fdbb8d52805` |
| local-node | `87110b1a6c6c4bb32d6299e663346c4051acca8ab5d971ab6956365ae75b9ac6` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Producer and consumer verify the exact runtime SHA, clean tracked/untracked
build inputs and actual package digests. The receipt's `source.dirty:true`
reflects untracked local review evidence outside build inputs; it is not a
fully pristine-worktree claim. No adapter overlay, Program patch or manifest
edit was used. This evidence-only update changes the report after the tested
runtime commit; submitted-HEAD CI is separate and recorded in the PR body.
