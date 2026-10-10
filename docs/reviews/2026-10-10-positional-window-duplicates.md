# Evaluated window slots in positional set operands

This is a frontend connection repair based on aggregate parent #1254 at
`131ff138fa9eb1b0292ae3e0337a4b8d1155af95`, which contains main
`179c0e9df04dab7195370d26db87280b05944078`. The parent remains an explicit
dependency until it reaches main. The adopted positional-set and duplicate
alias rules are recorded in [the scalar parent](2026-10-10-positional-duplicate-columns.md).

## Counterexample and independent expectations

```sql
DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x;
SELECT 0 AS a, 0 AS b
UNION ALL
SELECT ROW_NUMBER() OVER (ORDER BY x) AS n,
       ROW_NUMBER() OVER (ORDER BY x DESC) AS `N`
FROM r
ORDER BY a, b
```

The right rows are (1,2) and (2,1); the left row is (0,0). Expected public
rows are `[{"a":0,"b":0},{"a":1,"b":2},{"a":2,"b":1}]`, in a/b order,
both columns nonnullable numbers. Reusing one call's result would make both
columns equal. The right aliases do not determine public set names.

At the parent revision, with only the new regression added, JS failed with
`DuplicateOutput`: `run-pHqL5x` / `focused-test-H1OVQT`, 1/2 passed.
The independent ordinary JSON window/append/sort Program passed the same
checker. This is a demonstrated frontend refusal, not an executed wrong row.
The earlier built-runtime preparation probe is historical diagnostic evidence,
not a clean build of this submitted source or public acceptance.

## Minimal repair

Only repeated aliases in a terminal positional right operand receive distinct
private window slots. SELECT identifies each evaluated call using its full
window, function expression or scope-aware aggregate arguments, rather than
its repeated alias. The table belongs to one SELECT input snapshot and is
cleared at the window/SELECT boundary. It is not used for ORDER alias lookup.
Existing ordinal alignment exports the left names and removes private fields.

No common evaluator, window contract, Owner, wire, grammar, identity or limit
changes. Public and BY NAME duplicate outputs still refuse. Demanded duplicate
QUALIFY receivers require `AmbiguousColumn`; actual private slot names require
the ordinary expression lowerer's `UnknownReference`.

## Independent regression and public obligations

- A complete hand-authored DATA Values/analytic/select/append Program matches
  generated semantic Program exactly and both pass the ordinary checker.
- A separate ordinary JSON control uses two independently named window values.
- Opposing ORDER keys, ROW_NUMBER versus RANK on tied input, and SUM versus
  COUNT preserve function identity. SUM/COUNT use the already supported explicit
  ROWS frame and numeric contract fixture; default aggregate frames are not
  newly implemented by this repair.
- Empty input retains declared types; ordinary Values and Source paths are
  represented. One Source session, request reuse, rereading, describe types,
  column order and hidden-field absence use existing public checks.
- Six normal and two refusal fixtures enter both the ordinary corpus and its
  existing scoped packed consumer. Expected values are authored directly;
  the consumer never repairs generated Programs or infers types from rows.

The exploratory three-row RANK control exceeded the test helper's declared
20-step structure budget. The smaller two-row tied-input counterexample still
distinguishes ROW_NUMBER (1,2) from RANK (1,1), without changing checker limits.
The first SUM control lacked an explicit supported frame and numeric contract;
these fixture prerequisites were corrected without changing product contracts.

Authored inventory: 3,349 cases; 2,121 successes, 1,181 refusals and 47
execution failures. Historical source baseline `ce027a937` is retained.
Digest: `4a4529cb8e98c64f29193370424d150f8608e33657b5232c8b8d2dfb4dfdf69b`.
The scoped public consumer contains 66 cases per transport, 43 normal and
23 refusals, including all unchanged parent and adopted JOIN cases.

Focused counterexample/independent/refusal checks passed 5/5 at the pending
patch (`run-19fsRK` / `focused-test-0aTmOx`). Earlier direct window/QUALIFY/
aggregate callers passed 25/25 (`run-4BGyBA`). Final submitted caller counts,
exact-SHA normal five-package manifests and Local/HTTPS receipts are recorded
in the PR status after execution. Public completion and hosted CI are not
claimed by these lowering checks. Shared heavy-slot ownership is respected.
