# Shared CTE Source predicate repair

## Fixed input and expectation

Base main: `502618303520dbfaee15ea433d2fb13974316c3f`.
Product change: `39c85bc9162a2d44ffdbef21c3db0b0e2fe0f5ac`.

B's independent handoff is retained at
[8ec275bbf6543863955e4cae17c14ec8df14e00d](https://github.com/actql/actql/blob/8ec275bbf6543863955e4cae17c14ec8df14e00d/docs/reviews/2026-10-04-frontend-semantic-audit.md#current-cte-lowering-reproducer-and-ownership).
D owns this Source-predicate repair; it does not replace B's Graph-row lowering.

Submitted source, unchanged from the handoff:

```sql
WITH chosen AS (SELECT id FROM records WHERE id = 1),
     pairs AS (SELECT r.id AS id
               FROM chosen AS l CROSS JOIN records AS r)
SELECT id FROM pairs ORDER BY id
```

Physical input: `[{"id":1,"amount":null},{"id":2,"amount":20}]`.
Independent Named Result expectation: `[{"id":1},{"id":2}]`, with one
non-null number column `id` and one physical Source read session. `chosen`
has one row, while the JOIN-right operand consumes the complete Source.

The old compiler inspected only principal FROM references when deciding whether
to move the first CTE's WHERE into acquisition. It missed the JOIN-right Source
reference in `pairs`, filtered the common capture, and removed that WHERE from
the consumer. B's historical Local/HTTP wrong-row evidence remains historical;
the current-source failure below is a separately executed compiler regression.

## Existing-owner connection

`compile_cte_query` now counts Source references in all existing query terms and
JOIN operands under each nonrecursive CTE's lexical scope. A visible CTE alias
shadows the outer Source only after that alias is bound. Shared acquisition
keeps the complete capture and leaves each consumer's predicate downstream.
An unshared Source still retains its original acquisition predicate.

The terminal SELECT's single JOIN also resolves its right operand from the
already bound inputs, including an existing captured Stage Result. Its existing
StageResult guard remains required. The change adds no acquisition, does not
alter JOIN bounds, and uses the same Program/checker/planner/Run owners.

## Regression and acceptance status

`src/query_program/cte_capture_predicate_test.mbt` fixes the complete-capture,
consumer-predicate and single-input obligations independently. The alias control
uses a later `records` CTE derived from `chosen`; that JOIN must consume the CTE
Result, retain the unshared acquisition predicate and return only ID 1.

Before the product repair, pinned JS selection `CTE *` executed 9 tests:
8 passed and the shared-capture counterexample failed. After the repair,
the same 9 tests passed; broader existing CTE selection `*CTE*` passed 28/28.
Frontend/public-query fixture checks passed 10/10. Moon formatting and
`git diff --check` passed. These checks ran with the patch against the fixed
base above; the product commit records those source changes.

Local evidence is retained in this worktree's `_build/local-checks/attempts`:
`run-cIe3C3` (before), `run-6huTf4` (after), `run-oYdZkE` (broader CTE), and
`run-LWzJ2O` (Node fixtures). An earlier authoring attempt checked serialized
object-key order and was corrected before the fixed baseline failure was run;
it is not counted as an additional product defect.

Four authored public cases are registered in the normal
`queryCompositionSuccesses`, as well as its existing composition-only filter:
SQL/text versions of the original query, a terminal JOIN-right Source case,
and the lexical-shadowing control. The existing packed harness checks expected
rows, complete column contracts, row order, repeated read/attach and exactly one
physical acquisition on both Local and authenticated HTTPS. No separate CI job
or test-side Program repair is added.

Fresh-packed acceptance and exact submitted-HEAD required CI remain pending.
No full local Core, packed, proof or performance campaign was added. This repair
does not establish source-free Graph Result Policy binding or a remaining-active
temporary-holding inventory; those remain the A/D dependencies of #304/#182.
