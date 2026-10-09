# Ordinary aggregate inputs in inline OVER keys

## Scope and reference

This Frontend unit connects ordinary aggregates in inline window partition and
ordering expressions to the existing GROUP -> ANALYTIC Program. It introduces
no execution owner, aggregate implementation, capacity adjustment or Result
publication exception. The adopted main baseline is
`ef37a30df1bf63379be93dffdf9e2cfcad78ffd1`.

The selected [GoogleSQL window call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
place ordinary aggregation before window evaluation and permit aggregates as
window inputs. SELECT-owned arguments and OVER keys cannot use sibling SELECT
aliases, and a window cannot consume another window. This is an existing
semantic connection, not a new scoring, grouping or window law. The structural
grammar already admits expressions in partition and ordering keys; common
Program bodies, schema pins and their existing identities are unchanged.

## Pre-fix counterexample

```sql
SELECT t.x,
       ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, t.x) AS rn
FROM t
GROUP BY t.x
ORDER BY rn
```

With rows `(x,y) = (1,20), (1,21), (2,10)`, independently expected rows are
`[{"x":1,"rn":1},{"x":2,"rn":2}]`. GROUP has count 2 for key 1 and count 1
for key 2; ANALYTIC ranks descending count with the grouped key as a tie key.
Only x and rn are public, in that order. The complete expected Program was
authored directly in `window_group_aggregate_inputs_test.mbt`.

Before the fix, the independent Program checked but source parsing failed:
focused JS run `run-XVYJnM` / `focused-test-wFJH9S`, 1 passed and 1 failed.
The first attempted filename filter discovered zero tests and is not evidence
of a passing check. After the parser connection, an exact comparison exposed a
projection/sort layout difference; the oracle layout was corrected to the
existing selected-output ORDER placement without changing any value, ordering
term, count or public field.

## Change and ownership

- Inline OVER uses the existing bounded aggregate-expression extractor, and
  appends ordinary calls to its owning SELECT, QUALIFY or query ORDER call list.
- A whole SELECT window keeps its ordinary analytic output rather than creating
  an unnecessary scalar projection. Extracted aggregate slots remain private.
- The grouped window resolver uses retained input bindings and parser-owned
  aggregate references. When GROUP reuses a SELECT aggregate's evaluated slot,
  the window reads that slot without reevaluation or exposing sibling aliases.
- Query ORDER window keys retain ORDER ownership: their aggregate arguments
  resolve SELECT aliases before unqualified inputs, while qualified inputs
  preserve their input binding. The private GROUP outputs are mapped back into
  the ORDER window scope, including reused evaluated aggregates.
- Ordinary Pipe SELECT still does not insert an implicit aggregate stage.
  Existing nested-window rejection, argument checking and all capacity limits
  remain in their original owners.

No D-owned CTE/assert/Effect, A-owned evaluator, or C-owned Graph code changes.
No shared Owner dependency is required for this inline-key unit.

## Independent checks and public boundary

Focused JS selection: the new complete Program comparison, COUNT/SUM keys,
computed keys, aggregate partitioning, SELECT/QUALIFY/query ORDER ownership,
global grouping, aggregate-slot reuse, sibling-alias rejection and nested-window
rejection, plus existing named-window, scalar-window, grouped-clause and ORDER
window callers: **39/39**, `run-sUIsQL` / `focused-test-Z18nOu`.

Before the ORDER ownership correction, `SELECT t.y AS original, -t.y AS y FROM t
GROUP BY t.y ORDER BY ROW_NUMBER() OVER (ORDER BY SUM(y), original)` incorrectly
lowered SUM of input y, rather than SUM of the negative SELECT value.
`run-1kVGUo` / `focused-test-rzAD85` failed the discriminating assertion. For the
same three input rows the expected original order is 21,20,10, whereas the
incorrect input binding gives 10,20,21. The initial packed wrapper was stopped
while waiting for the verified shared gate owner, before any producer or
consumer started; it establishes no execution result.

Existing ordinary aggregate ORDER and star-replacement callers: **9/9**,
`run-xuN4wW` / `focused-test-4jqZTx`.

Final fixture checks: **4/4**, `run-374GcZ` / `focused-test-OYMke8`.
Commands use the pinned Node/MoonBit environment and existing bounded wrappers:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/window_group_aggregate_inputs_test.mbt \
  src/query_program/qualify_group_aggregate_slots_test.mbt \
  src/query_program/window_scalar_projection_test.mbt \
  src/query_program/analytic_order_expression_test.mbt \
  src/query_program/named_window_test.mbt \
  src/query_program/order_window_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/qualify-source-input.test.mjs
```

The existing ordinary and narrow packed QUALIFY consumers both include the new
fixtures. One independent JSON control and ten source cases compare ordered
rows and Result.describe column contracts. COUNT(nullable amount) deliberately
changes the expected ranking; duplicate source rows affect COUNT, while empty
input retains typed columns. Existing source acquisition, reread/attach/resend
checks and pre-admission refusal counters remain unchanged.

### Fresh packed Local/HTTPS evidence

The normal five-package producer and independent digest verifier used clean
source **`c43263ac9fdcd555e499762843bccf2adbd4e0a7`**. The external consumer ran
`node scripts/test-packed-public-query.mjs --qualify-only` without modifying
sources, Programs, rows, installed ceilings or Result contracts.

Both Embedded Local and HTTPS completed **43 positive cases, 12 pre-admission
refusals and one expected execution failure**. Eleven positive and two refusal
cases are new in this unit. The two new refusal codes are
`ClientProgramInvalidInput`; their assertions retain zero Run acceptance and
zero provider I/O. The consumer compares Result.describe contracts and ordered
rows, then rereads, reattaches and resends against the same Run without further
source acquisition. It also retains the existing analytic-property control.

- Bounded producer/consumer: `run-zrFh88`.
- Receipt:
  `/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-f5thIQ/summary.json`.
- Receipt source: clean c43263ac9; passed, complete, all ten commands exit 0,
  no signals or evidence errors; 2026-10-09 06:05:47.907–06:08:52.706 UTC.
- Successful external installation and Host artifacts were removed by the
  existing consumer after evidence persistence; original logs/receipt remain.
- Protected five-package manifest:
  `/private/tmp/actql-b-window-group-aggregate-c43263ac9-pack/packed-client-packages.json`.
- Bounded command wrapper:
  `/private/tmp/actql-b-window-group-aggregate-c43263ac9-packed.mjs`.

| Package | SHA-256 |
| --- | --- |
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `b65c18d27fd3ff64743ef6ea44b369d5325f95fb1bfb16d014912e718dd4c880` |
| local-node | `9261592af5c7e27f96f3f3ed5f918011c51d73bca02c283fc526662dccff0d1a` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The submitted revision adds this evidence record after the tested source; do
not relabel the c43263ac9 distribution as a later HEAD distribution. Submitted
HEAD CI, Wasm/Native execution, full Core, full packed suites, proof and
performance campaigns remain unverified. No live Google service comparison is
claimed.

## Remaining Frontend work

This unit does not establish aggregate extraction in WINDOW declarations or
window function arguments such as `LAG(SUM(x))` / `SUM(SUM(x)) OVER (...)`.
These remain separate Frontend connections to investigate and close, using the
same existing GROUP/ANALYTIC contracts. The ordinary named-window regression
selection above is preservation evidence, not execution evidence for aggregates
in those declarations. This PR is not a claim of complete window coverage or
completion of the overall text-to-Program goal.

## Subsequent main integration

Main `b987da2eae17e75dd76f641e6810cff7a252d053` was normally merged at
`5d7192a4b1de32b7be5759164450e3fe9353db17`. The merge preserves the current
recovery, value/field-name, managed completion, analytic-shape and immutable
release contracts from main. It changes no query_syntax source or this unit's
product lowerer/fixtures; existing query_program test updates from main remain.

The integrated grouped/window and ordinary ORDER caller selection passed
**48/48 JS tests**, `run-guPFlR` / `focused-test-SwOo0T`, using the same eight
selected test files above and the existing 180-second wrapper. This is the
integrated source's focused result, not a full Core or public execution result.
The c43263ac9 packed receipt remains historical exact-source evidence; no
integrated-HEAD packed/target CI success is claimed by this update.
