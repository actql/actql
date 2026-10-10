# SET over positional Pipe input

## Independent counterexample

At `b87b344e002a594d75dc156d6b5a0cc450325af2`, after adopting main
`16cebbe04d2265b290eb82abfe8ab69c05bfabc2`, this source refuses with
`UnsupportedProjection`:

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -x
  |> SET kept = kept + 10
)
ORDER BY a, b
```

For x=1,2 the independent rows are (0,0),(11,-1),(12,-2). The ordinary JSON
control derives negation, projects kept/neg, derives changed=kept+10, selects
changed/neg, aligns by ordinal, appends zero and sorts. It passes the common
checker. Baseline `run-I5j1pL` is 1/2: source refused, JSON passed. The saved
baseline is `/private/tmp/actql-b-positional-pipe-set-b87b344e0-baseline.mbt`.
This is a lowering refusal; no wrong public Run result was observed.

The existing SET contract in `docs/spec/query-text.md` retains visible column
order, evaluates siblings against the pre-SET snapshot and uses the replacement
value's checked type. Positional set alignment already retains anonymous
projection values. This repair connects those existing contracts, without
adding syntax, a common semantic law, an execution owner or a fallback.

## Minimal repair

The positional projection search stopped at SET and lost the earlier anonymous
ordinal role. Traverse this column-retaining operation. Check its authored
assignment expressions using the existing current Pipe scope, duplicate alias
and private-reference guards. Reject private targets before ordinary SET
matching; report ambiguous duplicate authored targets as AmbiguousColumn even
though their retained occurrences have distinct physical slots.

The ordinary SET lowerer still owns simultaneous assignment, evaluated slots,
types and final projection. Do not expose anonymous physical names, revive the
SELECT input/range or reinterpret ambiguous aliases as generated names.
Other owners' CTE, predicate, assert, Effect and execution work is unchanged.

## Focused evidence and public obligations

- `run-UKMFw2`: 6/6 changed-file JS tests pass, including an independent JSON
  control, chains/simultaneous siblings, duplicate aliases, typed private-name
  refusals and removed input/range refusals.
- `run-Ny1CQ0`: direct callers pass 23/23 JS tests (existing SET target/window,
  scalar REPLACE and window REPLACE). Its Node step is 49/50 because the
  independently asserted inventory totals had not yet counted the seven new
  normal and seven refusal cases. The overall guard remains failed.
- Update the independent totals by those fourteen authored obligations only;
  `run-8G9tkU` passes the affected inventory consumer, 36/36 Node tests. The
  SET fixture test already passed in the previous guard. No product code or
  expected row/type/order was changed to fix inventory bookkeeping.

The existing normal and selected packed registrations include eight new normal
cases: authored JSON control, source SET, quoted alias/filter/ordinal LIMIT,
current-expression ORDER/LIMIT, simultaneous swaps, retained duplicate values, nullable retained values and
empty typed output. Seven preparation refusals cover private target/receiver,
duplicate assignment, ambiguous target/receiver and removed range.

Public checks retain independent rows/order, complete Result.describe column
contracts and order, private-field absence, Source count, same-request reuse
and refusal before Run admission/provider I/O. No Program is patched by the
consumer. The selected cohort is 176 cases per transport (112 normal,
64 refusals). Full data-only registration is 3,459 obligations: 2,190 normal,
1,222 refusals and 47 execution-failure cases; digest
`9d4ebd39714e8eec85f58dddbf3f0b9f398e691d6fced9957565aacf1936180a`.
Registration is not execution evidence.

A current-value ORDER contrast adds one independent normal obligation:
`SELECT id AS id, -id |> SET id = -id |> ORDER BY -id |> LIMIT 1`.
For original IDs 2,1 the changed current key selects (-1,-1); reusing the
previous SELECT negation selects (-2,-2). The zero anchor makes public rows
(-1,-1),(0,0). Existing current-scope lowering already handles this after the
SET connection; no additional product change is needed. Hidden sort columns
must remain absent from Result.describe and rows. Final guard `run-lIYPBA`
passes 6/6 changed-file JS and 50/50 affected Node tests with complete
output/caller output, zero exit and released locks. Earlier failed guards
retain their original status. Source/caller changes were not repeated through
full Core or another backend.

This branch depends on #1299, which depends on #1297; the final destination is
main. Exact-SHA normal five-package Local/HTTPS acceptance and required CI
remain pending. No full Core, all-target, proof, performance, full packed or
Cloud campaign was run. Other column-edit composition remains independent
coverage, not a permanent language restriction. The wider frontend goal is
not complete.
