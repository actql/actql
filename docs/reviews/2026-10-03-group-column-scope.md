# Aggregation column scope: Frontend connection

## Baseline and dependency

This independent unit starts at
`6e85ad432ffb12dd0867843197a2ae728f139949` on
`feat/frontend-grouped-column-scope`. It depends on the unmerged JOIN chain
connection in [#266](https://github.com/actql/actql/pull/266); it does not replace
that PR's unchanged nine-positive/four-refusal execution target. Integrated
main is `b36d7864b57dc654cc03f583d8391e9ba2a506b3`, merged normally
through the JOIN parent. Existing history declarations are retained.

The imported-main foundation declaration failure remains a separate dependency.
No declaration, validator, workflow or common execution owner changes here.

## Existing semantics and implementation defect

The adopted [column scope](../spec/query-text.md#scope-and-lowering) and
[vocabulary criteria](../design/semantic-decisions.md#vocabulary-across-representations)
separate input range bindings, current Pipe columns and SQL output aliases.
SQL GROUP BY/HAVING applies the existing SELECT-alias rules. Pipe AGGREGATE
consumes the old input scope and produces only its grouping columns and named
aggregates; dropped input ranges do not reappear after it.
Google's [Pipe AGGREGATE reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#aggregate_pipe_operator)
also specifies grouping columns before aggregate columns. Its wider support
for grouping-item aliases, grouping sets and scalar expressions around
aggregates is not established by this unit's simple-key fixtures.

The previous scoped path projected current columns to their displayed names
before resolving GROUP BY and aggregate arguments. This discarded qualified
JOIN bindings and the original value retained by a Pipe alias after SET.
It could also try to project several JOIN inputs' same-named columns into one
ordinary Relation schema. These are lowering defects, not new restrictions on
the adopted language or missing common group semantics.

The parser now retains `GroupingScope::SqlSelect` or
`GroupingScope::PipeAggregate` on its common Group operation. That metadata
survives the defensive query accessor. It changes the Frontend AST interface,
not Program/wire/schema versions, a scalar type or the common group operation.
The generated interface is regenerated from source.

The lowerer resolves keys and aggregate arguments against the existing physical
slots. It does not materialize the entire displayed row first. SQL retains only
grouped input bindings until SELECT, supports HAVING through those bindings,
and reuses an already evaluated grouping expression. Pipe creates its new scope
after grouping and projects retained private key slots to the authored column
names. Its old ranges remain inaccessible with or without a preceding SET.

For the independently authored input `[{"x":7,"y":9}]`, after `AS before`
and `SET x = y`, current x is 9 while before.x is 7. Grouping by before.x
with SUM(x) and SUM(before.x) must reference three actual slots: original x,
the SET slot, and original x. The complete independent Program is in
[the regression tests](../../src/query_program/group_scope_test.mbt).
SUM still requires the ordinary common numeric profile; missing evidence stays
NeedsInputs. No Frontend evidence, alternate evaluator or runtime is introduced.

## Independent public acceptance target

[Six positive/four refusal fixtures](../../spec/frontend/fixtures/group-scope/cases.json)
are authored from the selected semantics, not compiler output. They cover:

- Original versus current key after SET: x=7 versus x=9, each with count 1.
- Computed SQL grouping alias, HAVING and ordered output through three JOINs.
- Pipe JOIN grouping followed by its new public x/n scope.
- Empty nullable grouping input with complete column contracts.
- One acquired producer reused by three JOIN inputs: counts 1, 1 and 8 for
  ids 1, 2 and 3, with one source acquisition session.
- Refusal of old ranges and ungrouped/dropped columns before Run admission/I/O.

The existing external-installation driver consumes the same fixtures on Local
and HTTP, including Named Result rows, full descriptions, attach, resubmission
and unchanged counters. Both the default corpus and the narrow selector use
the normal package producer and common Host:

```sh
node scripts/test-packed-public-query.mjs --group-scope-only
```

These public targets are **not executed** at this checkpoint. They do not
establish packed execution, capacity admission or all aggregation combinations.
No prior #246 JSON composition result is used as text execution evidence.

## Focused evidence and unfinished coverage

The changed group tests plus existing compile/JOIN tests passed 73/73 on JS.
After adding the complete independent Program assertion, selected group/parser
tests passed 20/20. The initial SUM test correctly returned NeedsInputs without
the numeric profile; the corrected test asserts that requirement before checking
with the existing declared profile. That initial failure is not counted as a
successful test or a removed common check.

The new parser metadata/accessor regression passed 17/17 with the existing
parser cases after correcting its test-only constructor qualification. Changed
Node scripts pass syntax checks; document links and whitespace are checked
separately. None of those checks executes the prepared public fixture rows.

At integration `a2659718d18265b1359339293294fff277aa7ee8`, the selected
grouping test file passed 5/5, including a loop over all six authored positive
sources through script lowering and ordinary admission/checking. The acquired
input was represented by Values in that focused test; this does not establish
source acquisition or public Host execution.

A separate one-case Local JSON control passed using the unchanged installed
packages from source `6a351574c88e316269214046ddcb7a1164db8351`.
It submitted the independently authored expected Program, rather than a
compiler-generated expectation. Rows were
`[{"x":7,"current_value":9,"original_value":7}]`; describe returned x,
current_value, original_value in that order, with the ordinary number and
nullable contracts. Same-request retry and Result rereading preserved the
Run and rows. This older-package control establishes common execution of
that expected IR only, not fresh-source Local/HTTP acceptance or CI success
for this branch.

Public Local/HTTP acceptance and same-source PR CI remain unfinished. FULL JOIN,
wider collection/frame combinations, NEAREST's installed Host connection and
the full language migration remain separate obligations. No full local Core,
packed suite, proof campaign or new native runtime build was requested here.
