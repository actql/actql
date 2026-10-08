# NEAREST candidates through existing Script input binding

Date: 2026-10-08. B's Frontend connection unit. Target: main; the NEAREST
member-binding parent has now merged. This is separate from INFER acceptance
and D's CTE/predicate/Effect implementation.

## Fixed counterexample

```aql
DATA qs = FROM queries;
DATA cs = FROM candidates;
FROM qs AS q
|> NEAREST cs AS c
   QUERY KEY (q.request_id) VECTOR q.embedding
   CANDIDATE KEY (c.item_id) VECTOR c.embedding
   METRIC dot K 2
   KEEP (q.note, c.label) AS neighbor
```

The inputs in `nearest_context()` are typed closed VALUES already supported by
the common checker. The independent `nearest_shared_program(true)` also checks.
Before the change, `lower_script_relation_term` did not supply `nearest_inputs`
to `compile_steps`; the candidate lookup therefore had no entries. Pre-fix
`run-Fr35vA` failed 0/1 selected test at Frontend compilation after the independent
machine control had checked. No public Host failure is claimed for that probe.

The new private `bind_script_nearest_inputs` uses the existing
`nearest_dependencies` resolver and `bind_script_input` producer/capture owner.
It passes each bound candidate to `compile_steps`. Existing DATA aliases keep
their relation names and can share a physical producer. A candidate that is the
selected input reuses its binding. No Model, Source, CTE evaluator or acquisition
owner is added; predicates, keys, metric, K and KEEP arguments are unchanged.
The call-site addition does not modify D's CTE, predicate, assert or Effect code.

`nearest_script_test.mbt` fixes a full ordinary Program independently of compiler
output. Its VALUES and NEAREST expressions come from the existing handwritten
machine fixture; the Script's binding names and Result port are specified
explicitly. The generated complete Program matches. Common checking also covers
two aliases of one retained seed, nullable KEEP and both typed key roles. The
many-to-one joins are retained; a query key alone is not declared unique.
Undeclared/forward candidates retain `UnknownRelation`.

## Separate CTE handoff for D

`fixtures/nearest-cte-candidate-repro.aql` uses the same input and expected two
rows as `spec/frontend/fixtures/nearest-keep/expected-rows.json`, with the same
column contracts and declared order. It currently returns `UnsupportedCte`.
The parser already resolves the candidate's lexical CTE name correctly.
`query_cte_scope.mbt::validate_cte_scope` marks FROM and JOIN references as uses,
but does not mark NEAREST candidate references. Consequently its final unused-
declaration check rejects `cs` even though NEAREST consumes it.

D's change needs to count resolved candidate references in both the terminal
query's uses and the transitive used-CTE walk; validation must retain lexical
scope, undeclared/forward-reference rejection and one shared Source acquisition.
B has not modified that function. The named test preserves the exact current
refusal as an implementation gap, not a permanent language restriction. Convert
it to a positive control and register the saved source for public acceptance
when D's scope fix is adopted. This refusal is not counted as CTE execution
success or evidence that the entire NEAREST Script surface is complete.

## Verification and pending public boundary

Base: NEAREST parent `a6014b5ed15ac40d029fa4459ab5478f869a31c3` plus normal merge
of main `f2ceac7e0c673780b053b9a323e76a03c152e09a` as
`de322f3ec394eca52258114b0ba0b56f9a87a3c3`. No conflicts or history declaration
changes. The unpublished merge title was corrected to Conventional Commits.

- `run-uF1HfF`: initial connection, 12/12 JS.
- `run-qHyXKY`: extended controls, 14/15; the additional CTE positive exposed the
  separate scope owner gap above. No expected row, K or key was weakened.
- `run-ZnmqZf`: 15/15 focused JS across `nearest_script_test.mbt`,
  `nearest_test.mbt`, `data_script_test.mbt`; 2/2 existing Node fixture tests.
- Selected formatting and `git diff --check` passed.

These are working-revision checks, not clean submitted-HEAD execution or CI.
No full Core, target matrix, proof, performance or repeated packed suite ran.

The parent #942/#952 revisions subsequently merged into main
`f299df8092021f3f8fe5d3072a57a512c9dd7872`. The normal merge into this branch is
`fa702123f2b89e28832bcd1d3c8e11de710cbdfa`, with no conflict. `run-yvx6cR`
passed the same 15/15 selected JS tests on that clean integration SHA; this is
local evidence only. The subsequent delivery-record update changes no executable
input and does not convert this result into CI or public execution evidence.

The existing `nearest-public-input.mjs` inventory adds the complete DATA source
with the unchanged independent rows/contracts and a forward-candidate refusal.
Its existing consumer verifies Named Result rows, column order, streams,
describe/re-read, same-request retries and observation counters on Local/HTTPS.
The actual typed Source installation is still a separate unfinished boundary;
no array coercion, schema override or alternative VecA executor is supplied here.
Public execution of this source is pending and cannot be inferred from successful
lowering/checking. INFER, Graph and the full Frontend objective remain open.
