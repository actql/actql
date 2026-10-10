# Correlated UNNEST over positional Pipe projections

## Existing requirement and baseline

Correlated UNNEST expands the current Relation, retaining evaluated parent
occurrences. Anonymous and duplicate authored columns are valid positional set
operands. ARRAY bounds, NULL/empty expansion, duplicate child rows and optional
INNER predicates belong to the existing common checker and execution owner.
This connects those contracts, without adding a new row-expansion meaning.

Baseline `1db718add4eabaec5018773f32d7e86d954958a4` normally merges main
`6899e712d4413934c8750faaf6584266f81ef1b3`, including merged DISTINCT #1319.
This complete source fails specifically with UnsupportedProjection:

```aql
SELECT 0 AS a, 0 AS b, 0 AS c
UNION ALL (
  FROM t |> SELECT x AS kept, -y
  |> CROSS JOIN UNNEST([10,20]) AS element
  |> SELECT *
)
ORDER BY a,b,c
```

Changing the first projection to ``x AS v, -y AS `V` `` fails with
DuplicateOutput. Input (1,10),(2,20) independently requires the anchor and four
expanded rows: (0,0,0),(1,-10,10),(1,-10,20),(2,-20,10),(2,-20,20).
An independently authored JSON Program derives neg=-y, projects kept/neg,
derives the ARRAY, applies ordinary unnest, selects a/b/c, appends the anchor
and explicitly sorts the Named Result. It passes the existing checker.

Baseline `run-3bOmev` is 1/3: JSON control passes, both source forms fail.
Preserved source tests:
`/private/tmp/actql-b-positional-unnest-1db718add-baseline.mbt`.
Independent Program, input and rows:
`/private/tmp/actql-b-positional-unnest-next-candidate.json`.
These failures establish a compiler gap, not incorrect published Run results.

## Cause and repair

Pipe dispatch treated correlated UNNEST as an ordinary independent JOIN and
captured the preceding projection before the positional set operand role could
reach it. Positional role discovery also stopped at UnnestSource. Fixing only
the latter leaves both failures unchanged (`run-dxGKwP`, 1/3).

Reuse the existing quoted-token-aware correlated-UNNEST lookahead at the next
Pipe operator. Keep correlation in the same operation sequence rather than
creating an independent JOIN input. Ordinary Relation JOIN capture and explicit
JOIN bounds retain their existing dispatch. Continue positional role discovery
through UNNEST; validate ARRAY expressions against current visible occurrences,
rejecting private or ambiguous authored references. Reserve later element and
OFFSET names before allocating private positional storage names.

No common UNNEST kernel, source acquisition owner, capacity limit, contract,
schema pin, fallback, diagnostic SDK or consumer-side Program correction changes.
Private-name-like authored aliases remain usable; no prefix is forbidden.

## Independent public obligations

Twelve normal cases cover the complete JSON control, anonymous and duplicate
projections, current-value ARRAY construction with OFFSET, SET plus an immutable
range, INNER filtering including a NULL element, nullable elements, duplicate
elements, typed empty output, private-name-like element/OFFSET destinations and
a nullable parent value. Seven preparation refusals cover private anonymous
arguments, bare/qualified ambiguous aliases, dropped input, old input ranges,
qualified private values and a non-ARRAY argument.

The public Source declares amount nullable, so the public JSON control declares
y nullable and the expected b contract remains nullable even for non-NULL rows.
The baseline nonnullable JSON control is separate. Rows do not determine types.
Expected values, multiplicity, types and column order are independently authored.
The existing public consumer checks Named Result, Result.describe, explicit
order, hidden-column absence, one Source acquisition, same-request Run reuse
and zero admission/provider I/O for preparation refusals.

## Validation and remaining work

After repair, `run-hoxCX8` passes 3/3 fixed baseline/control tests. Expanded
`run-hxVc8g` passes 29/30: product/caller tests pass; the new parser-only test
incorrectly inspected the outer parenthesized set binding as its operation body.
That independent parser assertion now uses the direct Pipe query to isolate
correlation dispatch. `run-7zTS3n` passes 1/1; product code is unchanged after
the expanded check. Ordinary JOIN capture, correlated star, positional DISTINCT,
argument ambiguity and private-name refusal checks are preserved. No unaffected
successful tests were repeated only to produce a new aggregate total.

`run-xPZr8Q` passes 56/56 targeted Node tests (20 fixture, 36 inventory).
Pinned MoonBit formatting and `git diff --check` pass. All guards have terminal
records and released locks; failed baseline guards are not described as passes.

The normal inventory registers 3,571 occurrences: 2,251 normal, 1,273 refusals,
47 execution failures; digest
`93ec689ebc1e26a42b43f7316786e8e38affedcd362e6f94186ebb9ad12e2a7c`.
The existing selected cohort has 288 cases per transport: 173 normal and
115 refusals. Registration alone is not execution evidence.

At this commit, normal clean-HEAD five-package packed Local/HTTPS execution is
pending. Full Core, Wasm/native, the full packed corpus and CI are unverified.
No unmerged parent dependency remains; destination main. The broader frontend
goal remains incomplete.
