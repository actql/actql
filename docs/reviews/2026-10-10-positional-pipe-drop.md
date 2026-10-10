# DROP over positional Pipe input

## Preserved counterexample

Adopted main: `f4a878bd27f5b42e59b0ee610bf08d3ea17a9ebd`.
For x=1,2 and y=20,10 this authored source must yield
(a,b)=(0,0),(1,-1),(2,-2):

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, y AS removed, -x
  |> DROP removed
)
ORDER BY a, b
```

Baseline `run-xe7GWj` ran three focused JS cases: the DROP and RENAME sources
both failed with UnsupportedProjection; the independently authored ordinary
JSON controls passed the common checker. This was 1/3, not a public wrong-result
observation. Original source is preserved at
`/private/tmp/actql-b-positional-pipe-edits-f4a878bd2-baseline.mbt`.
RENAME remains a separate unresolved frontend unit; this DROP repair does not
claim to close it or restrict its adopted meaning.

## Existing contract and repair

The selected GoogleSQL Pipe DROP removes every occurrence of an authored
column name while retaining other columns. Positional sets match by ordinal.
Repository `docs/spec/query-text.md` also preserves current-column edits and
range snapshots; no contract or owner change is needed.

Retain the earlier positional SELECT through DROP. Check authored DROP targets
before admitting private names. Reuse the star-exclusion correspondence from
physical duplicate occurrences to authored names; then pass those occurrences
to the existing DROP implementation. Anonymous values remain evaluated slots,
not authored receiver names. Missing targets and repeated targets keep their
ordinary typed refusals; duplicate aliases can all be removed without choosing
an arbitrary occurrence. No old SELECT input or range is restored.

The shared correspondence helper has the same loop and result as the existing
star-exclusion closure. Existing star-exclusion, SET, range-collision, UNNEST
and JOIN callers are selected for focused regression. No new resolver, owner,
wire format, capacity change or consumer-side Program patch is introduced.

## Independent public obligations

Eight normal cases include an authored JSON control, submitted DROP source,
all duplicate aliases removed, unrelated duplicate values retained, sequential
quoted DROP plus ordinal LIMIT, filter/expression LIMIT, nullable value and
typed empty output. Seven refusals cover private/quoted targets, repeated
removal, removed current name, removed input ORDER, old range and ambiguous
retained alias ORDER. Expected rows and complete ordered column contracts are
authored; the consumer does not patch the generated Program.

These are included in normal packed registration and the existing selected
cohort. Selected registration: 191 cases per transport, 120 normal and 71
refusals. Full data-only registration: 3,474 occurrences, 2,198 normal,
1,229 refusals and 47 execution failures; digest
`c960ba85a1429062336c18fff863d37d9f896a617ce0ee04f0e3e1b8efd5ff61`.
Registration is not execution evidence.

Public acceptance must compare Named Result values/order, Result.describe
column types/nullability/order, hidden-field absence, one Source acquisition,
same-request Run reuse and rejection before Run admission/provider I/O.
The explicit JSON control uses Values and therefore has zero Source reads.

## Validation status

Initial DROP-only guard `run-08OnXX`: 2/2 JS pass after the product change.
Focused guard `run-AqBnWD`: 31/31 JS cases pass across the changed DROP
file and directly affected star exclusion, SET, ordinary range collisions,
UNNEST and JOIN callers. An earlier expanded test did not compile because its
new test matched an Issue where Expression holds a Diagnostic; `run-0FEXHj`
remains failed, with no executed-test success claim.

Node guard `run-pK1Rai` is 50/51: all 36 inventory consumer tests pass, but
the fixture file's independent total still omitted the new eight normal and
seven refusal obligations. Update only those authored totals (99+8 normal,
58+7 refusal); `run-YeI2Mq` then passes the affected fixture file, 15/15.
Product code and expected row/type/order values are unchanged by that
bookkeeping correction. Earlier failed guards remain failed.

Formatting and `git diff --check` pass. Exact clean-SHA normal five-package Local/HTTPS acceptance and
submitted-HEAD required CI remain pending. No full Core, all-target, proof,
performance, full packed or Cloud campaign is claimed. The wider frontend
goal remains active.
