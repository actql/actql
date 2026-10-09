# JOIN set operands: standalone query entry connection

Authoring main: `b40818e09295dba39de6b570b977610e95c75b1e` (#1079 included).
This independent unit has no unmerged parent. Final target is main.

## Fixed counterexample and implementation boundary

```sql
SELECT t.x AS id FROM t JOIN r ON t.x = r.k WHERE t.x = 1
UNION ALL
SELECT t.x AS id FROM t JOIN r ON t.x = r.k
ORDER BY id
```

For t.x=[1,2], r.k=[1,2], the independently intended rows are id=[1,1,2].
The complete hand-authored ordinary Values/filter/join/append/sort Program
passes common checking. The existing single-query script route also passes;
the standalone compile entry refuses exactly UnsupportedJoin. Pre-repair
focused test: 0/1 (`run-VT0oYb`, `focused-test-HL81G9`).

The standalone entry previously chose compile_set_query, whose
compile_set_stages rejects any JOIN operand. DATA already uses
lower_script_set_relation and lower_script_join_relation. Route only query
trees with a JOIN set operand through this existing script path. Inspect nested
set rights and CTE bodies structurally; do not resolve names, move WHERE/ON,
change key mappings or add another execution implementation in that router.

The one call-site adjustment is compile.mbt::compile. D's CTE/predicate/assert/
Effect functions, query_script_program, common Owners, Host, grammar, pins,
physical strategy and capacity rules are unchanged. The new module handles
structural entry selection only. No shared producer is expanded or materialized.

Existing composition requirements in docs/spec/query-text.md apply. The selected
[GoogleSQL query syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#set_operators)
combines query operands; [JOIN](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#join_operation)
retains matching multiplicity, while final ORDER/LIMIT belongs to the combined
output. Existing adopted set-name/CTE profiles remain unchanged. Current official
reference was consulted; this is not a live Google differential run or complete
query conformance claim.

## Independent public obligations

The new set-join-source-input fixture participates in the existing normal
public corpus and --set-corresponding-only cohort. Old twelve normal/eight
refusal CORRESPONDING cases remain unchanged. Add eight normal/four exact
refusal cases, not a second Host or test-side Program repair.

- Independently authored JSON captures the shared source once and applies both
  filters/joins, append and final sort using ordinary operations.
- Complete SQL uses explicit MAX_OUTPUT_ROWS 10 for both JOINs, exactly matching
  the JSON control. It does not depend on the public default of 1,000,000.
- Rows id=2 are duplicated twice; their self-JOIN yields four matching rows.
  UNION ALL retains all four. A NULL amount remains NULL and sorts last.
- Right-only JOIN operand, reversed CORRESPONDING field order and a CTE set body
  retain six intended rows and the public id/amount column order/contracts.
- Empty input retains typed empty results. Explicit typed LIMIT/OFFSET parameters
  select two duplicated id=2 rows. UNION DISTINCT retains one row per value.
- Operand ranges and the right-only output alias do not escape the set. Missing
  limit declaration and unsupported JOIN keys retain exact preparation refusals.
- Existing acceptance checks Named Result, Result.describe, hidden field absence,
  same-submission replay/attach/lookup and one physical source acquisition session.

## Limited validation

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- --target js src/query_program/set_join_entry_test.mbt src/query_program/data_set_test.mbt src/query_program/data_join_test.mbt src/query_program/set_order_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/set-join-source-input.test.mjs scripts/set-corresponding-source-input.test.mjs
```

The first post-repair selection passed 12/13: ten existing caller tests and two
new tests passed; the last new assertion used the wrong take field name (limit
rather than the existing count contract). After correcting that authored
assertion, 2/3 passed with the remaining exact refusal expectation located at
Expression(UnknownReference), not UnsupportedSet. The final new selection passed
3/3 (`run-J89iIR`, `focused-test-TeOWUa`). The unchanged ten caller cases were
not needlessly repeated. Node fixture registration/expectations passed 4/4
(`run-LyJWXP`, `focused-test-z6ML8p`); the explicit-bound fixture adjustment also passed 4/4 (`run-usIzS6`,
`focused-test-oLV4dS`).

The initial preparation record left public Local/HTTPS execution, normal five-package identity, submitted-HEAD CI
and content review unverified. Later exact-source evidence is recorded below;
keep Draft until the public obligations and submitted-HEAD checks are complete. Full Core, Wasm/native, proof/performance and the
full packed campaign were not selected locally. This unit does not claim the
entire Frontend complete.


## First normal packed execution and the alignment counterexample

Normal producer source: `2f98fb9a41a77679429924972d39a261abc9d766`.
The five tarballs were produced by the existing producer with ordinary prepack
and independently checked against its revision/digest manifest. The consumer
receipt is `worktrees/.codex-scratch/public-query-evidence-4E6bC1`; bounded
producer/consumer attempt: `run-Miz3YR`. Retain that receipt and the producer
manifest/tarballs separately from later source revisions.

Packed Local passed twelve unchanged CORRESPONDING controls plus the new
independent JSON, both-JOIN-operands SQL and right-only-JOIN SQL. It then failed
at set-join-sql-corresponding, before Named Result publication. The four later
positive cases, all refusals and HTTPS were not reached. These fifteen passes
are partial Local evidence, not complete acceptance or CI success. The six
expected rows, JOIN ceilings of 10, nullable amount, column order and one-source
acquisition obligation remain unchanged.

The terminal ACTQL_E_UNPUBLISHED_RUN is not the first cause. A focused private
diagnostic reinstalled the same digest-verified tarballs, added an existing
Host diagnostic callback with an explicit temporary account/key/reviewer, and
used an inspector breakpoint without editing a package. Source acquisition
completed. The captured execution had host-tasks-failed, no completed tasks,
and Physical(ExecutionLimit); publication subsequently reported
StrategyNotComplete/CapturedRunPublicationFailed. Source Run failure is verified;
the diagnostic authorization/observation setup is not the pristine acceptance
installation. Evidence: `run-WBFhzZ`, `run-aIw4OS`, and the protected private
`actql-b-set-join-2f98fb9a4-diagnostic/publication-cause.json` and Store. Earlier
diagnostic setup failures (wrong working directory, missing helper fixtures and
installation callback mismatch) are not product failures or test passes.

The same packaged preparation API checked and compiled the ordinary JSON and
both SQL cases, and saved their complete semantic Programs and Executable Plans
(`run-AeZHFD`, `focused-test-NJm6vK`). The reversed-order SQL's only additional
operation is a second immediate select after the JOIN's terminal column
projection: select amount/id, then align id/amount.

## Narrow projection composition

Compose those adjacent pure column projections inside the existing set lowerer.
The new helper accepts only an operand-local terminal step with exactly
from/select/as and column strings or column aliases. It preserves the evaluated
column sources, the producer name and the required set output spelling/order.
It does not move across another operation, modify predicates/ceilings, evaluate
an expression twice, or add identity/order evidence. Previously declared
producers, expression-valued projections and retained Result taps are excluded.
The query entry keeps the existing NEAREST/Graph placement refusals before
selecting the JOIN/set script route.

Changed shared call site: query_script_set.mbt::lower_script_set_relation, only
the immediate right-operand alignment. CTE source-sharing/predicate/assert/Effect
functions and query_script_program are unchanged. This is one Frontend
implementation; common capacity/strategy/Host Owners are not duplicated or
relaxed. D's composition paths consume this same set lowerer after integration.

Limited JS tests passed 6/6 (`run-MPYYLF`, `focused-test-RIo9qa`): the five JOIN
entry tests plus independently authored projection/strict-boundary cases. Eight
existing set caller cases passed with the same product change in the preceding
13-case selection (`run-0AFh7a`); only the new test initially chose a JOIN that
had no terminal select to compose. Its source was corrected to exercise the
actual qualified/filtered JOIN path. Test setup/compiler errors are not passes.

A new clean source and normal pack must establish whether this removal closes
the public ExecutionLimit. Keep all twenty positive/twelve refusal cases and
Local/HTTPS obligations; do not change the budget or exclude the failing case.

## Exact b183 source execution and first-cause isolation

Normal producer source: `b1832bd42fac1dd879dc23a6f7257dbd984ac749`.
The unchanged normal external consumer passed sixteen Local positives (the old
twelve controls and four new controls, including reversed CORRESPONDING), then
failed at set-join-cte-set-body. Remaining cases and HTTPS were not reached in
that normal run. Receipt: `worktrees/.codex-scratch/public-query-evidence-dB5il9`;
bounded attempt: `run-62RMPt`. The five retained tarballs are in
`/private/tmp/actql-b-set-join-b1832bd42-pack`:

| Package | SHA-256 |
|---|---|
| client-wire | 18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905 |
| sdk | c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c |
| run-host-core | 332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d |
| local-node | 53b05ae615be878bf6c018fc0a2bfbf0b8a4505acfd6db7c43d057f73549812e |
| node | 2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda |

A subsequent diagnostic reused these verified packages and the original eight
new success/four refusal fixtures. It invokes the unchanged public helper once
per case, records assertion failures, continues to HTTPS and exits nonzero if
any case failed. No source, expected rows/contracts, parameter, ceiling or
package implementation was changed. This is a focused retained-package
diagnostic, not a successful pristine campaign. `run-yzqUCu` and
`/private/tmp/actql-b-set-join-b1832bd42-diagnostic/retained-set-join-results.json`
record each mode: five positive cases passed (JSON, both JOIN operands, right
JOIN, reversed CORRESPONDING and typed empty), all four exact preparation
refusals passed with zero admission/source I/O, and CTE, parameter LIMIT and
UNION DISTINCT failed before publication. Named Result values, describe columns,
NULL/multiplicity, one acquisition and replay assertions remain unchanged.

Read-only inspector breakpoints with the existing diagnostic account/observer
isolated each failure to task 1 ManagedStart -> Physical(ExecutionLimit), before
attempt consumption. Each actual siteCapacity was retainedBytes=14,240,000,
executionBytes=563,431,936; the standard execution ceiling remains 536,870,912.
Zero reservedExecutionBytes after rejection is not evidence that the operation
fits. These diagnostics do not prove a common capacity overestimate.

The CTE's generated ordinary Program, submitted unchanged as JSON, also failed
(`run-M0RU8p`). Its source and Program preparation/Plan check passed
(`run-wA1LNK`); LIMIT and DISTINCT preparation/Plan passed (`run-cuytmi`,
`focused-test-wITU8O`). LIMIT/DISTINCT root-cause observation: `run-LLBfkA`.
Generated reproductions are retained in the adjacent `fixtures/set-join-b183-*`
files. They are observed implementation outputs, never independent expectations.
The expected rows/contracts remain authored in set-join-source-input.mjs.
Protected private diagnostic files and cause-state Stores retain full evidence;
do not copy credentials or journal custody into this document.

## Eliminate the final identity projection within the set lowerer

For each failed Program the set lowerer appends a column-identical SELECT only
to bind its final structural output name. The set owner has already aligned
operand columns, applied DISTINCT/ORDER/LIMIT and removed hidden ORDER slots.
For the JOIN-bearing set route, rebind that last locally generated producer
instead of allocating the extra projection. Preserve every operation and
argument, including parameterized count/offset, typed columns and order.
Previously created/shared steps and retained Result taps are excluded. Other
set entry routes retain their existing structure. No capacity coefficient,
Host ceiling, physical strategy or common Owner changes.

This change is confined to query_script_set.mbt::lower_script_set_relation and
query_set_projection.mbt. D's CTE source-sharing, predicate, assert and Effect
functions are not edited. The inner CTE set may use this same ordinary set
lowerer; there is no separate CTE implementation or test-side Program repair.
The initial counterexample selection passed 5/6 before this change: the new
output-binding invariant failed (`run-uxbLiY`, `focused-test-ahIRjB`). The first
setup failure with an unavailable test helper was not a semantic reproduction.
After repair, JOIN/projection plus eight existing DATA/CORRESPONDING caller
cases passed 15/15 (`run-m02egh`, `focused-test-c6EWc5`). The final focused
selection, including parameter/body preservation and shared-step exclusion,
passed 8/8 (`run-vhWXTX`, `focused-test-jMm0le`). Its earlier wrong reader API
was a test compilation error, not a pass. Pinned formatting and diff checks
were selected; no full Core/all-target/proof/performance checks were run.

A new normal clean-source producer and unchanged Local/HTTPS cohort must verify
all twenty positives/twelve refusals. The three prior failures remain recorded;
none is excluded or relabeled as an expected successful rejection. Required CI
and content review remain separate from local evidence.

## Completed normal public acceptance at the repaired source

Clean producer/consumer revision: `5552c96a9716eb40d5038c3db20f68f42fb0f09c`.
Bounded attempt `run-QAbGHa` exited 0. Receipt
`worktrees/.codex-scratch/public-query-evidence-hiTFiI/summary.json` records
passed/complete, clean source, each child command and captured stdout/stderr.
The unchanged standard external acceptance.mjs command exited 0 after 75.1s.
Embedded Local and actual TLS HTTPS each passed all twenty positives and twelve
preparation refusals. This includes every original new JOIN case: independent
JSON, both operands, right operand, reversed CORRESPONDING, CTE set body, typed
empty, typed parameter LIMIT/OFFSET and UNION DISTINCT. None of the previous
three failures was skipped or converted into an expected execution failure.

Named answer rows and actual Result.describe column types/order match the
independent fixtures. Duplicated id=2 self-JOIN rows, nullable amounts, explicit
filters, JOIN ceilings of 10 and count/offset values are preserved. Full row
comparisons exclude internal columns. The existing helper confirmed one physical
Source acquisition session per source-backed case; Result reread, attach,
resubmit and lookup performed no extra admission/acquisition. All preparation
refusals performed no admission or provider I/O. The standard Host execution
budget is unchanged. These passes establish the repaired Frontend Programs fit
that budget; they do not establish that the old capacity derivation was wrong.

The ordinary producer used all five package prepack steps; no adapter overlay,
runtime patch, Moon test bridge or test-side Program correction was applied.
The retained manifest at `/private/tmp/actql-b-set-join-5552c96a9-pack` records:

| Package | SHA-256 |
|---|---|
| client-wire | 18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905 |
| sdk | c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c |
| run-host-core | 332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d |
| local-node | f11505f527b41feb4a182a7bf008d1763f8e2a242b98352058cbbbb018160bc1 |
| node | 2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda |

The bounded invocation used pinned Node 22.22.0/Moon 0.10.12+1634b282e and:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-set-join-5552c96a9-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-set-join-5552c96a9-pack ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-set-join-5552c96a9-pack/npm-cache node scripts/test-packed-public-query.mjs --set-corresponding-only
```

The private wrapper `actql-b-set-join-5552c96a9-packed-20261009.mjs` applies the
existing runLocalCheck heavy lock and 1200s total budget and independently
verifies the manifest revision and five digests between producer and consumer.
Readme Local/HTTPS and fourteen existing profile fixtures also passed inside
the normal driver; that incidental coverage is not a full packed campaign.

The subsequent evidence-only commit does not change the tested implementation
and is not claimed as a new five-package build. Submitted-HEAD required CI,
content review, full Core, Wasm/native, proofs/performance and the entire packed
campaign remain unverified. Main was fetched after the diagnostic and still
points to authoring baseline b40818e09295dba39de6b570b977610e95c75b1e. Final target
is main with no unmerged dependency. Keep the submitted PR Draft pending its
own review/required checks; do not manually rerun CI or merge it here.

This selected JOIN/set entry and its public obligations are complete locally.
The broader Frontend goal and the independent #1081 common BETWEEN execution
dependency are not closed by this result.
