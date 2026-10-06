# Grouped single-JOIN source connection

Owner: B. Parent PR: #509 (`fix/frontend-having-aggregates`). Fixed parent SHA:
`9679a37fadf16ac676e16b62b1a99f46ec9aa9a9`, including current main
`64046e37a1cadb2148edeab7cbf85b96d125b518` by normal merge. The final merge
target remains main; retain the parent base until #509 reaches main.

## Counterexample and contract

The [HAVING report](2026-10-06-having-aggregate-source.md) retains the exact
single-JOIN source and independently expected `[{"id":1,"n":2}]`. At its first
packed SHA it was refused before acceptance even though its ordinary JSON
control later passed on Embedded Local and HTTPS. The old alias predicate
`HAVING n > 1` also produces the same typed `UnsupportedCte` at that boundary.

An additional independently written full Values Program in
`src/query_program/single_join_group_test.mbt` passes the common checker at the
fixed parent. Its source fails compilation before this repair (0/1,
`_build/local-checks/attempts/run-Z688ca`). The expected Program is written from
existing join/group/filter/sort/select contracts, not copied from compiler output.
It retains the authored JOIN ceiling 10, both checked input ports, an evaluated
group key and the declared public field order.

GROUP/HAVING/SELECT consume the joined row in that order. The projection-only
single-JOIN path expects SELECT as its first non-WHERE operation and cannot
supply the required grouped input scope. Existing multiple-JOIN lowering
already keeps each range and physical column separately and delegates its tail
to `compile_steps`. This is a Frontend connection gap, not a new common Group
or JOIN execution contract.

## Repair and boundaries

`join_requires_group_scope` identifies an existing Group operation. Only queries
with at least one JOIN and that operation use the existing scoped lowering for
the single-JOIN case. Ordinary ungrouped single-JOIN queries retain their existing
specialization. The shared scoped helper accepts its matching two-input case,
still validates input count against JOIN count, and retains the same key
resolution, authored ceilings, range snapshots and common operation records.

The four caller branches are standalone SQL (`compile`), outer CTE SQL
(`compile_cte_query`), a CTE body (`compile_cte_stage`), and source/DATA script
(`lower_script_join_relation`). Zero-JOIN GROUP queries keep their old route.
No CTE validation, source predicate, assert, Effect, Model original-wire,
cancellation, capacity derivation, physical strategy, runtime owner or Ledger
cleanup implementation changes here.

D's published #465 changes were inspected at
`de3abafc012ca3682d68d63d001e365a2e6cc393`; they were subsequently adopted
through current main. They contain no overlapping Frontend JOIN edit. The
earlier proposed CTE/JOIN handoff is superseded by this bounded B-owned repair;
it is not a dependency wait for D's current correctness unit.

## Independent acceptance

The exact original source is restored as a normal public case, with unchanged
predicate, ceiling, rows and column contracts. The former known-gap refusal is
removed rather than kept alongside the now-supported path. The full JSON
control remains independent.

Additional authored cases distinguish:

- Shared-Source self-JOIN: two occurrences of IDs 1 and 3 each yield four joined
  rows, rather than two. The source is acquired once.
- LEFT JOIN: unmatched right keys remain NULL; COUNT(*) for ID 3 is two while
  COUNT(right key) is zero. Both counts are nonnullable numbers.
- CROSS JOIN global aggregation: WHERE excludes ID 0; the aggregate is six.
- GROUP inside a CTE and global aggregation on empty input: typed ordered
  columns remain available and the empty global COUNT is zero.
- Non-equijoin and ungrouped input refusals occur before admission/I/O. A JOIN
  ceiling of one remains one and fails execution with no readable or
  describable Result; it is never replaced by the default ceiling.

These cases join the ordinary packed corpus and its existing narrow HAVING
selection. There is no new acceptance framework. Each normal case compares
rows, complete `Result.describe()` column contracts/order, one acquisition,
stable Run identity and no extra acquisition/acceptance after read/attach/resend.

Validation results and final-SHA package digests are recorded separately in the
PR body and external evidence. No full Core, all-target, full packed, proof,
performance or Cloud campaign is claimed by this unit.
