# JOIN row expressions through the existing scope

## Problem and selected contract

An ordinary range is a non-NULL closed object over its declared evaluated
fields. The input range overrides a same-named column; ORDER output aliases
have their separate nearer scope. See [the scope rules](../spec/query-text.md)
and [the adopted precedence correction](2026-10-11-range-name-precedence.md).
The selected GoogleSQL name-scope evidence is pinned to
[`d82db99a923a46571f543a13899dc791a7b6f743`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/name_scope.cc).

The two-input JOIN projection specialization could not construct the row.
The preserved prototype at `2fff853ea04ca01aca8179e02f842eeda2c36573`
connected row fields, but still preferred a same-named scalar column:

```sql
SELECT l AS row
FROM (SELECT 7 AS l,9 AS id) l
CROSS JOIN (SELECT 2 AS id) r MAX_OUTPUT_ROWS 10
```

The independent expectation is `[{"row":{"l":7,"id":9}}]`, not scalar 7.
Its focused regression failed before the final routing correction (2/3,
`run-vLiWIO`). The original source-only baseline and independent checked JSON
are retained at `/private/tmp/actql-b-whole-row-join-followup.json` and
`/private/tmp/actql-b-joined-row-range-c130cb46f-baseline.mbt`.
These compiler observations are not public execution evidence.

## Implementation and ownership

Route whole-row expressions, including a pre-JOIN WHERE, into the existing
`JoinChainScope` and expression binder. Remove the prototype's duplicated
row collection/slot construction from the JOIN projection specialization.
The shared scope already carries declared operand fields, original USING
keys, value-table kind, null extension and the ORDER alias namespace.
Unchanged scalar-column JOINs retain the existing specialization.

No new JOIN/evaluation owner, source acquisition, storage format, key proof or
capacity rule is introduced. FULL JOIN continues to need its existing checked
identity evidence: its normal fixture supplies explicit `ASSERT UNIQUE BY`.
A known row with a missing member reaches the existing closed-object checker
and is rejected with `UnknownField("missing")`; an unavailable range remains
an unresolved reference. The old parenthesized-receiver collision expectation
is corrected using the selected name-scope rule, not observed product values.

Main `e99a3c01a1a59c8be027fbaae6f555561647d898` is merged normally at
`0833c2c07060c6ed8291341ddfe3db718c6909a0`. Its PIVOT argument changes, CI and
history records are preserved. The direct dependency is the submitted #1359
at `2cdd01b81ca0ff2645132dbeb827a183b7442860`; no dependency PR is merged here.

## Independent acceptance and verification

The ordinary packed composition corpus contains 11 new normal cases and four
typed refusals, with no Program repair after lowering. A hand-authored JSON
control and authored source have the same expected values and declared columns.
Cases cover NULL fields, duplicate rows, empty input, quoted ranges, input-name
collisions, LEFT/RIGHT null extension, keyed FULL USING, pre-JOIN WHERE/LIMIT,
ORDER alias reuse, and a shared acquired CTE with six expected matches and one
Source read session. Every public row contains only the explicit Result fields.
The ORDER counterexample sorts IDs 1,2,2 using the output row; reusing the
selected original amount sorts IDs 2,2,1 and cannot satisfy the fixture.

Focused checks after the correction:

- JS: 38/38 directly affected row, property, ORDER, outer-JOIN, precedence and
  consuming Values Run tests (`run-PwBe96`).
- Node: 83/83 independent preimages, fixture policy and registration tests
  (`run-VkrTAi`).
- Compilation/document/spec/canonical/Workers/Node freshness checks pass
  read-only. MoonBit formatting and `git diff --check` pass.

Query-rule metadata changes grammar `7b70ef4ac9e85715f6fb01cf692fa4a3811bdd4b1fef96d5ae132de2613e8d6d`
to `d2dc38cdf444ff4a60d0096fa4bf486b392526231336d20b4628d6321bb50990`.
Syntax and common expression/JOIN contracts are unchanged. Complete previous
Run preimages remain in `scripts/fixtures/pre-joined-row-range-values-identities.json`.
Independent sorted JSON rehashing yields current Values Run
`b20b5b1274cc9aba4d8b04257ed7acec3418eb1f782e634031365b5150c66331`;
Unit, Program, ResultPlan and value identities remain unchanged. Historical
grammar-bound Runs are not relabeled.

The registered full inventory has 3,789 authored occurrences, not 3,789 executed
cases. This unit selects the existing 119-case composition cohort (81 normal,
38 refusal). Clean fixed-SHA five-package Local/HTTPS execution is recorded in
the PR only after its terminal receipts and package correspondence are checked.
Before that evidence exists, public execution remains unverified. Full Core,
Wasm/Native, all packed corpora and hosted CI are not established by these
focused checks. The broader Frontend goal remains active.
