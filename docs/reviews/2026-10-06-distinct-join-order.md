# DISTINCT JOIN ordering preserves projected values

Baseline: `8f6133865d37f6ece67284e34172372cf7dcffca`.
This repairs a frontend connection gap within existing query scope and ordinary
Relation contracts. It does not change grammar, schemas, common laws or pins.

## Contract and counterexamples

The adopted query profile allows ORDER expressions that can be resolved from
DISTINCT output values. Output aliases take precedence; qualified input columns
survive only when their values were directly selected. This follows the existing
[query contract](../spec/query-text.md#scope-and-lowering) and the selected
[GoogleSQL query reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#order_by_clause).
Ordinary SELECT already connected this case, while the single JOIN/CTE JOIN
helper rejected every ORDER expression that did not directly reuse a SELECT
expression or name.

The three independently authored baseline tests all failed (`run-9NMYzN`,
0/3), including SQL alias shadowing, a directly selected qualified input,
Pipe JOIN and CTE JOIN:

```sql
SELECT DISTINCT -t.x AS x
FROM t JOIN r ON t.x = r.k
ORDER BY -x;
```

The ORDER negation consumes the evaluated output x. It cannot reuse the SELECT
negation of input t.x, nor recover that dropped input. Baseline evidence is
compiler rejection, not an executed public Run with incorrect output rows.

## Repair and independent expectations

Both Values JOIN assembly and retained/CTE JOIN assembly preserve their existing
JOIN, predicate, ceiling, projection and DISTINCT. Non-reusable ORDER expressions
are checked against projected aliases and direct selected-input correspondence.
They lower through existing property-aware expressions to ordinary derive steps
*after* DISTINCT. Existing sort, LIMIT/OFFSET and final projection then remove
helpers. SELECT expressions are not expanded or evaluated again. Non-DISTINCT
assembly and exact selected-expression reuse retain their existing paths.

A full expected Values Program is hand authored and passes normal checking before
comparison with source lowering. It includes both input Stages, JOIN ceiling 4,
projected score, DISTINCT, a qualified-input-derived sort helper, sorting and
public projection. It is not generated from product output. Exact
`UnsupportedOrdering` tests preserve refusal of dropped input columns and
transformed input recovery; duplicate ORDER expressions share one helper.

Focused repaired-tree JS checks passed 30/30 (`run-EopLn5`):

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/distinct_join_order_test.mbt src/query_program/join_order_test.mbt src/query_program/distinct_order_output_test.mbt src/query_program/join_property_paths_test.mbt src/query_program/data_join_test.mbt
node scripts/local-checks.mjs test node -- scripts/distinct-join-order-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

Node fixture/profile/corpus checks passed 9/9 (`run-e3useB`). Selected formatting,
JavaScript syntax and whitespace checks passed. These are focused precommit
implementation-tree results, not hosted CI or other-target results.

## Public acceptance obligations

The authored packed corpus contains an independent JSON control, SQL alias
collision, Pipe LIMIT/OFFSET, one shared acquired CTE producer, selected qualified
input ordering, exact selected-expression reuse and typed empty output. Input
amounts 2,2,1,NULL plus excluded 99 yield DISTINCT output NULL,-1,-2 when ordering
by the negated output alias; ordering a directly selected input yields 1,2,NULL.
Three dropped-input cases must fail preparation with no Run admission or provider
I/O. A demanded divide-by-zero in the ORDER expression must fail execution and
publish no partial Result.

The normal corpus and narrow `--distinct-join-order-only` selector share these
fixtures. Existing public acceptance compares rows, ordered schema and complete
type/nullability, hidden-column absence, acquisition counters and same-request
resend/attach/reread. JOIN ceilings are authored as 25 for the five-row source;
no ceiling or execution budget is raised to obtain success. Public execution
results and exact package/runtime identities are recorded separately after
normal committed-source packing.

No common owner, planner, provider or Host implementation is changed. Full Core,
other targets, all packed/proofs/performance and hosted required coverage remain
unverified by the selected checks. No merge or manual CI retry is performed.

## Public-route failure and follow-up repair

Normal packing at `1db7f63023176811a44c74e190f14f4dcd2a92b8` produced
receipt `public-query-evidence-iKCR3N` (`run-3fr0h4`). The independent
JSON control passed Embedded Local, but the first raw SQL request was refused
with `ClientProgramUnsupported` (422), before later cases or HTTPS were reached.
This is retained failure evidence, not public completion.

The standalone query dispatcher selected the Values-only JOIN assembler, which
rejects a context with a captured Stage. A separate acquired-input counterexample
failed 0/1 in `run-91UKtC`. The existing Script JOIN assembler already binds
acquired producers once and calls the same JOIN lowering. The dispatcher now
uses it when a captured Stage is requested, even without DATA declarations.
It neither rewrites the submitted source nor modifies an emitted Program.
The original Values-only path remains unchanged for its existing context.
No CTE predicate, assert, Effect, Host or execution-owner implementation is edited.

The final focused JS selection passed 42/42 (`run-7SQYIo`):

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/acquired_join_order_test.mbt src/query_program/distinct_join_order_test.mbt src/query_program/join_order_test.mbt src/query_program/join_chain_test.mbt src/query_program/data_join_test.mbt src/query_program/join_property_paths_test.mbt src/query_program/distinct_order_output_test.mbt
```

Additional coverage retains authored filter equality, ceiling 25 and refusal
under a lower declared construction ceiling, range-name collision refusal,
one declared acquired input, and nullable selected-property ordering through
the ordinary checker. Normal committed-source packing must be repeated because
compiled inputs changed; the previous tarballs are not relabeled as this source.

## LIMIT/OFFSET capacity boundary remains open

Normal clean-source packing at `4435dd8637b41e4b42da3e56b6a5712a6faaf22c`
produced receipt `public-query-evidence-Jzshqr` (`run-442aUJ`). The independent
JSON control and raw SQL alias-collision case passed Embedded Local. The Pipe
LIMIT/OFFSET case was accepted but ended without publication. Later normal cases,
refusals, execution-failure cases and HTTPS were not reached in this invocation.
A same-package retained rerun (`public-query-evidence-r3QMdX`, `run-25fHYz`)
confirmed the same failure; it is not additional completion evidence.

A one-request diagnostic reused that exact installed package/runtime. It used
public installation authorization/observation and a diagnostic-only in-memory
loader to print existing checked Program, capacity and stored execution errors.
Package files, generated Program, provider behavior, limits and expectations were
not modified. This loader diagnostic is distinct from pristine packed acceptance.
`run-UoarjU` exposed `LocalManagedStart -> Execution -> Physical(ExecutionLimit)`;
`run-zjOkAD` recorded the capacity below. Task 1
required 546,445,568 execution/scratch bytes, with 14,240,000 retained bytes and
1,000,000 transfer bytes. The installed execution budget remains 536,870,912 bytes.
Acquisition completed; no Compute task completed. The subsequent
`StrategyNotComplete` and `ACTQL_E_UNPUBLISHED_RUN` are downstream symptoms.

The captured [checked Program](fixtures/distinct-join-order-pipe-limit.program.json)
is retained as generated reproduction material, **not** as an independent
lowering oracle. It preserves JOIN ceiling 25, `l.id > 0`, DISTINCT over the
selected amount, ORDER over the evaluated alias, and take count 2 / offset 1.
Its [expected rows](fixtures/distinct-join-order-pipe-limit.expected.json) are
independently authored. No budget, expected row, sort or LIMIT is removed.
Common reservation/capacity changes remain the execution owner's boundary;
this evidence does not establish that the derivation is excessive.

Current main `ccf8d0b340578756ab6889debc047c20db24883d` was normally merged
without conflicts before continued verification. Previous-SHA results stay
attached to their original source/package manifest; they are not relabeled as
integrated-HEAD acceptance.

The saved generated Program was also submitted unchanged with `format: 'json'`
through the same retained public installation. It reproduced the identical
546,445,568-byte task reservation and `Physical(ExecutionLimit)`, without invoking
query lowering. This isolates the rejection after frontend preparation; it does
not prove that capacity should be reduced. All nine main-stage operations retain
needed JOIN fields, the authored predicate, selected projection, DISTINCT,
post-DISTINCT ORDER helper, sorting, take, and public-column removal. No redundant
frontend operation has been established by this inspection.

Integrated-tree focused checks passed 42/42 JS (`run-wBjIiy`,
`focused-test-oyrqzi`) and 9/9 Node. The direct JSON capacity diagnostic was
`run-Cfp7IA`. These checks do not establish the outstanding public Pipe execution.
