# Correlated UNNEST: existing common expansion from public text

Base: main `4ceb8b6f97674b9b9d0edbc2dbae4541187d5d22`. Independent branch:
`feat/frontend-correlated-unnest`. This unit does not depend on the pending
literal membership or Graph quantifier PRs and adds no execution owner.

## Fixed counterexample and reference

```sql
SELECT p.id, element, position
FROM parents AS p
CROSS JOIN UNNEST(p.items) AS element WITH OFFSET position
ORDER BY p.id, position
```

The independent Values input has `(id, items)` rows `(2, [2,NULL,2])`,
`(1, [1])`, `(3, [])`, `(4, NULL)`. The ordered output is:

```json
[{"id":1,"element":1,"position":0},
 {"id":2,"element":2,"position":0},
 {"id":2,"element":null,"position":1},
 {"id":2,"element":2,"position":2}]
```

The [GoogleSQL array expansion reference](https://docs.cloud.google.com/bigquery/docs/arrays#converting_elements_in_an_array_to_rows_in_a_table)
defines per-row correlation, parent-column retention and OFFSET. These are
selected semantic obligations, not a claim of full correlated JOIN support or
a live differential run against BigQuery.

Before implementation, the hand-authored complete JSON Program passed the
ordinary checker, but the equivalent SQL failed parsing. The retained failing
selection is `run-O9crpo`, `focused-test-fwknhe`: 0/1 passed. No public Run
failure was demonstrated by this compile-boundary regression.

## Connection and scope

SQL and Pipe CROSS JOIN UNNEST dispatch to the existing `UnnestSource` operation.
Lowering resolves the expression in the current preceding row scope, copies its
evaluated value to a private array slot, and emits common `unnest` with optional
`with_index`. Parent columns/ranges survive; nothing is silently removed from
the source or re-evaluated by a second executor. Ordinary JOINs preceding
correlation use the existing general joined-row scope.

Successive closed object expansions retain every original value receiver.
SET changes the current column while a preceding range still names its original
slot. SELECT/AS replace that scope under the existing rules. Unknown child
contracts do not prevent an unrelated qualified parent star. Common checking
owns ARRAY admission, NULL propagation, key transfer and expansion capacity.
The Frontend does not declare a parent key unique after one-to-many expansion.

The public corpus contains thirteen positive cases and eight pre-admission
refusals. It includes an independent JSON control, row-dependent ARRAYs,
duplicates/NULL elements, NULL/empty ARRAYs, parent stars, original versus current
SET values, explicit filtering/LIMIT, DATA, and one-acquisition ordinary and
joined parents. The normal corpus and focused Local/HTTPS consumer both register
the same fixtures. No test patches the generated Program.

## Identity and evidence

Existing generators update grammar, complete normative import metadata and
canonical vectors. Grammar CID:
`sha256:669a907108617a89e253dcf5d5f5ef88fe14ec46fe84df18bb6e4d22638347f5`.
The complete hand-assembled Values Run preimage independently yields
`sha256:4ca80c7d99dd7834c8fc281ce2aff63833e52711eb52702c2cc628c361a01af4`.
Its predecessor grammar/Run pair is retained; no saved Run is relabeled. Values
Unit, cardinality proof, Result Plan and common operation meanings are unchanged.

Focused JS regressions, including existing UNNEST callers, passed 13/13:
`run-1iH1Vc`, `focused-test-dRTqHI`. Earlier additional assertions exposed two
test-fragment mistakes (`run-ZZp92Y`) and an overly broad parent-star guard
(`run-oa4JSr`); both failures remain separate evidence. The latter was fixed by
using the parser's actual star receiver expression, without rejecting parent
projections. A Node manifest check exposed incomplete generated metadata
(`run-fR4vJJ`, 15/16); the normal metadata/canonical generators repair that
closure, rather than suppressing the check. The repaired focused Node selection
passed 16/16 (`run-wLlAIM`, `focused-test-j9YRL0`). The affected Values Run
material boundary passed JS 1/1 (`run-RNPlV6`, `focused-test-h9NElK`).
Read-only manifest, metadata and canonical-vector checks pass (375 vectors);
formatting is checked only for the changed MoonBit files.

Fresh five-package production and public acceptance must use the clean committed
source and `node scripts/test-packed-public-query.mjs --correlated-unnest-only
--keep-artifacts`. At this source commit they are pending, as is submitted-HEAD
CI. Local checks do not certify all backends or full integration.

## Remaining coverage

Ordinary Relation JOIN after expansion, INNER/LEFT correlation, implicit comma
expansion, Pipe-set tails and stars requiring an unknown ARRAY element schema
remain explicit coverage gaps. These are not restrictions of GoogleSQL and are
not implementation completion. Unsupported placement is rejected instead of
reordering consumers or changing multiplicity. The common declared ARRAY bound
and Host capacity policy remain in force; no capacity ceiling is raised.
