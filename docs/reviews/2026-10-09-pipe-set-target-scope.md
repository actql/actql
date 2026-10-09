# Pipe SET: reject ambiguous current targets

Date: 2026-10-09. Status: minimal Frontend correction and focused checks passed;
fresh packed Embedded Local/HTTPS and submitted-HEAD CI are not yet established.

## Existing requirement and counterexample

Adopted main is `ffe46cdae6d064a60da517dec2937eeaee4a1c30` (fetch reconfirmed).
Parent #1125 remains unmerged at `478a3981ec439f7830ce694861197e325de4100c`,
following #1121/#1116/#1115/#1111. Final integration target is main.

The normative query-text SET section already requires each target to exist
exactly once. The selected
[GoogleSQL SET reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#set)
also distinguishes current columns from immutable range values. This is an
implementation correction within that contract, not a new restriction.

```aql
FROM t AS l
|> RIGHT JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10
|> SET x = 99
|> SELECT l.x AS left_x, r.x AS right_x
```

Both operands expose a current x. SET must reject its ambiguous target even
though its value is constant and the final SELECT names qualified inputs.
Baseline `run-KnO4aJ` / `focused-test-JMqDDl` fails 0/1: the compiler accepts the
input and emits an ordinary JOIN plus `derive: {aql_pipe_set_4: {literal: 99}}`.
The test retains the complete accepted Program in its failure log. This proves
incorrect compiler acceptance, not a pre-fix public Run execution failure.

An earlier DATA/CROSS JOIN probe stopped at existing UnsupportedCte before this
target boundary (`run-OcYLOr` / `run-04M2xc`). It is not evidence of this defect
or a reason to change D's CTE handling. The RIGHT JOIN probe reaches the shared
joined-row scope and isolates the actual SET target defect.

## Minimal correction and independent controls

`compile_steps` previously tested only whether any current column matched the
target, then replaced every matching visible binding. SET now counts matches
under existing identifier resolution: zero gives existing UnknownColumn, more
than one gives existing AmbiguousColumn, and one follows the unchanged assignment
path. Duplicate assignment targets retain DuplicateOutput. DROP's deliberately
different multiple-match semantics and the general presence helper are unchanged.

Four bare/backtick case variants are checked with scalar and inline window
assignment values. Refusals assert the exact cause, not Err(_). The independently
authored complete ordinary Program verifies RIGHT JOIN conversion, original
range slots, replacement slot, projection, Result fields and MAX_OUTPUT_ROWS 10.
A separate common checker test accepts USING's single coalesced current target
even though both immutable operand ranges retain their own key slots.

The existing normal/focused JOIN-star public cohort gains four positive controls:
independent JSON, equivalent text, an unmatched nullable original range and
coalesced USING. Independent rows distinguish replacement values from original
values and retain duplicate multiplicity (six self-JOIN rows, including four
id=3 pairs). Describe contracts preserve column order and replacement/original
nullability. Eight exact-code target refusals cover bare/backtick case variants
with scalar/window assignments and require zero Run admission and Source I/O.
No lowered Program is repaired by the test. Existing shared acceptance checks
retain acquisition once, same-Run resend/attach/reread and unchanged counters.

No grammar, Program, expression, identity law, serialization, checker, provider,
capacity, Result order, diagnostic owner or pin changes are required. Source
predicates, JOIN arguments, limits, row/schema expectations and execution owners
remain unchanged. No fallback or separate execution path is introduced.

## Focused evidence and remaining coverage

Pinned JS, through the bounded/nonzero wrapper:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/pipe_set_target_scope_test.mbt \
  src/query_program/pipe_set_window_test.mbt \
  src/query_program/pipe_join_ranges_test.mbt \
  src/query_program/full_join_scope_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/join-star-source-input.test.mjs
```

JS: 16/16 (`run-pgpy4Z`, `focused-test-9AfvMt`). Node: 3/3 (`run-YyeCnR`,
`focused-test-EjyKXA`). Independent controls also passed 3/3 before the expanded
window refusal coverage (`run-orZbpP`). Formatting and diff whitespace checked.

Fresh normal five-package packing and the existing `--join-star-only` Local/HTTPS
consumer remain to be executed. Submitted-HEAD CI, three-target runtime coverage,
full Core/full packed/performance and live Google differential execution remain
unverified. Draft preparation is not merge CI; the broader Frontend goal remains
active. No other worktree, D's CTE/assert/Effect code or common execution owner
was edited.

## First packed attempt: independent control correction

Normal five-package production and exact revision/digest verification passed at
`7cf526f286794126ca25a0fc3ae16a0066d4b789` (`run-K8Fytl`). The existing ten
Local positives passed before the new independent JSON control was rejected
at preparation with ClientProgramInvalidInput. Receipt
`public-query-evidence-JQCgSD` retains complete command 010 streams and exit 1.
Later positives/refusals and HTTPS are not established by this run.

The independent JSON authoring error was a snapshot derive map writing current
over an already selected current column. The normative derive map is add-only;
ordered derive arrays have their own shadow contract. The control now selects
only original/matched and adds current as a new slot. No expected value, type,
column order, multiplicity, limit or Source acquisition count changed. The
Frontend correction and its independent complete MoonBit Program remain
unchanged. This is a fixture correction, not a product execution fix or an
adjustment of the desired public result.
