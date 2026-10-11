# Positional PIVOT implicit keys and source scope

## Existing requirement and matched-input counterexample

The adopted Pipe PIVOT profile groups by current columns not consumed by its
aggregate argument or axis, in current order. It reuses evaluated slots,
including immutable range receivers. Anonymous and duplicate authored columns
remain valid positional set input; the common checker and PIVOT Owner determine
groupability, NULLs, aggregates, output types and capacity.

At main `3d58815fa679de2a3bc41eadaa97d616383337ff`, this complete source fails
specifically with UnsupportedProjection:

```aql
SELECT 0 AS a,0 AS b
UNION ALL (
  FROM t |> SELECT x AS amount,-y,'A' AS axis
  |> PIVOT(SUM(amount) AS total FOR axis IN('A'))
  |> SELECT *
)
ORDER BY a,b
```

The anonymous -y is an unconsumed numeric grouping key. For matched input
(1,10),(2,20),(3,10), expected rows are (-20,2),(-10,4),(0,0). Dropping that
key incorrectly combines the two groups. The independent JSON control derives
neg/axis, selects amount/neg/axis, pivots with index=[neg], selects a/b,
appends the anchor and sorts. It passes the same checker. Baseline `run-ziUQH8`
is 1/2: control passes, source fails. No incorrect public Run is claimed.

Preserved source/control tests:
`/private/tmp/actql-b-positional-pivot-3d58815fa-baseline.mbt`.
Independent input, Program, source and expected rows:
`/private/tmp/actql-b-positional-pivot-next-candidate.json`.

## Main adoption and minimal repair

After #1335 reaches main, normally adopt fixed main
`5bcbebd61da51c40b1b5276593f9d818e3a69fb7` (fast-forward). Reuse its shared
positional reference guard rather than introduce another resolver. The incoming
ASSERT connection, contracts, independent vectors, generated pins and CI remain
unchanged. No unmerged parent dependency remains; final destination main.

Continue positional role discovery through PIVOT. Reserve authored generated
bucket names before private-slot allocation. Resolve the aggregate and axis
paths in current scope and pass both through existing ambiguity/private guards.
The ordinary PIVOT lowerer compares authored grouping names when checking a
generated-name collision; private storage names cannot conceal an authored
collision. A legitimate bucket resembling a private name remains usable.

The PIVOT operation and its existing input index/value/axis semantics, declared
bucket order, fresh output scope and type/NULL checks are retained. There is no
new grouping/aggregate/execution Owner, identity pin change, capacity exemption,
implicit sort or consumer-side Program correction.

## Independent fixture correction and limited checks

After repair, `run-yX2f7p` passes 2/2 matched source/control tests. Expanded
`run-AJOabw` is 23/24: the new positive loop stops at its first immutable-range
example. Splitting without changing sources/expectations (`run-x43dER`, 7/8)
isolates only UnsupportedSet in that newly authored example.

That fixture incorrectly gave the left anchor two fields. After SET amount=7,
SUM(r.amount) consumes the original slot, so current amount remains an implicit
key alongside anonymous -y. Complete output has three fields: current amount,
negative y, sum of original x. With the matched input above, independent rows
are (0,0,0),(7,-20,2),(7,-10,4). Correct the newly authored left anchor to three
fields; dropping a key or changing the product to force two would violate the
existing rule. Original counterexample/product remain unchanged by this fix.
Rationale and prior source are retained at
`/private/tmp/actql-b-positional-pivot-immutable-shape-correction.json`.
Only the affected new test file is rerun: `run-52pRf2` passes 8/8. Existing
passing PIVOT/assertion/UNPIVOT/positional-helper callers are not repeated solely
to produce a clean aggregate total.

Targeted Node `run-SVTZNQ` passes 60/60 (24 fixture, 36 inventory). Pinned
MoonBit formatting and `git diff --check` pass. Guards are terminal and release
locks. Failed baseline/diagnostic guards remain separately preserved.

## Public obligations and remaining execution

Nine normal fixtures cover the JSON control, anonymous grouping key, duplicate
group occurrences, immutable aggregate receiver plus current key, current SET
aggregate, authored bucket order/COUNT zero, legitimate private-name-like bucket,
nullable key and typed empty keyed input. Source/control use matched row values.
Public Source amount is nullable, so the JSON control declares y nullable and
the expected grouping output keeps that contract. SUM outputs remain nullable
even for this non-NULL input; rows do not narrow a schema.

Seven preparation refusals cover private aggregate paths, ambiguous aggregate
or axis, qualified ambiguity, authored generated-name collision, dropped input
and old output range. Existing consumer checks Named Result rows/multiplicity,
explicit order, complete describe types/nullability/column order, internal-column
absence, Source acquisition and same-request reuse. Refusals retain typed
ClientProgramInvalidInput and zero Run admission/provider I/O. No independent
expectation is authored by reading the compiler's result.

Registration includes the existing normal and selected consumer. Full inventory
is 3,677: 2,314 normal, 1,313 preparation refusals, 50 runtime failures; digest
`66eb3300caff76a142e6c473997728bb3cf93449ef888ddf48000b7f27fe31cd`.
Selected registration is 350 per transport: 209 normal, 139 preparation refusals
and the two retained assertion runtime failures. Registration is not execution.

At this commit normal exact clean-HEAD five-package Local/HTTPS acceptance is
pending. Full Core, Wasm/native, full packed corpus and CI remain unverified.
The broader frontend goal remains incomplete.
