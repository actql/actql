# Positional Pipe assertion scope

## Existing requirement and fixed counterexample

ASSERT UNIQUE BY lowers to the existing `assert_rows.unique_by` operation and
preserves the current row and surviving range bindings. It does not deduplicate,
infer a key from ITEM KEY, or replace the common non-null/present/unique checks.
Anonymous and duplicate authored occurrences remain valid positional set input.

Main `dc64badc6fe43f0da9550422a0637fff35abb4d7` is normally adopted through
merge `d13c6d9b82f3a65dc200856db96924ecc71c4b87`. Its new common contracts,
generated pins, independent vectors and CI configuration are retained. This
complete source fails specifically with UnsupportedProjection:

```aql
SELECT 0 AS a,0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept,-y
  |> ASSERT UNIQUE BY(kept)
  |> SELECT *
)
ORDER BY a,b
```

The independent ordinary JSON control selects kept/neg, asserts uniqueness of
kept, selects a/b, appends the anchor and sorts. It passes the same checker.
Baseline `run-hV03SE` is 1/2: JSON passes, source fails. This establishes a
compiler/checker gap, not wrong public execution. The compiler probe uses the
existing nonnullable x/y test context (1,20),(2,10); the initial independent
JSON example uses (1,10),(2,20). Their concrete rows are not compared as equal
Programs. The rejection occurs before execution and is independent of those
values. Public source/control below use matched (1,10),(2,20) inputs and expect
(0,0),(1,-10),(2,-20).

Preserved baseline:
`/private/tmp/actql-b-positional-assert-d13c6d9b8-baseline.mbt`.
Independent source, Program, input and expectations:
`/private/tmp/actql-b-positional-assert-next-candidate.json`.

## Frontend-only repair and ownership

Continue positional projection discovery and whole-row AS-star discovery through
AssertUnique. Its key paths resolve against current evaluated occurrences.
Extract the existing positional expression-reference guard into a local closure
and apply that same guard to assertion paths. Expression checks retain their
original order and concrete failure families. Private anonymous slots, bare or
qualified duplicate aliases, dropped input and displaced ranges remain refused.

The existing AssertUnique lowering branch is byte-identical to the adopted
baseline. D's ASSERT parser/body, CTE/Effect code and common assertion checker/
execution owner are unchanged. This repairs B-owned role/name scope only;
there is no second key resolver or execution path, invented uniqueness,
capacity exemption, contract/pin change or consumer-side Program patch.
The D worktree was only read for overlap: the relevant files were clean.

## Independent public obligations

Nine normal cases cover the complete JSON control, anonymous source, qualified
row star, immutable range key after SET, renamed current key, duplicate values
with a separate usable key, nullable nonkey, typed empty input and declared
parameter/filter/ORDER/LIMIT. In the immutable case current kept=7 repeats while
r.kept still names the distinct original values: selecting the wrong key must
fail rather than pass that normal expectation.

Six preparation refusals cover anonymous/private, bare/qualified ambiguity,
dropped input, displaced range and qualified private keys. They retain the
ClientProgramInvalidInput check and zero Run admission/provider I/O. Two
separate runtime failures supply duplicate IDs with different amounts through
JSON and text. The existing Owner must fail the accepted Run, expose no Result,
and preserve failed status on attach/resubmit without further acquisition.
These cases detect mistakenly asserting the distinct negative amounts instead
of the duplicate IDs. They contain no Model operation; this is not new evidence
for Model-dispatch fencing or D's composite INFER/Effect/restart unit.

Public Source amount is nullable, so its independent JSON control declares y
nullable. Result.describe must retain that type even for particular non-NULL
rows. The existing consumer verifies values/multiplicity/order, complete types,
column order, hidden-column absence, Source acquisition and same-request reuse.
No expected values or Programs are generated from compiler output.

Runtime failure registration uses the existing executionFailures path in both
normal and `--set-corresponding-only` consumers. No new flag, harness, Owner or
limit is added. The original Graph repeated-failure occurrences are retained;
their later positions shift by exactly the two inserted runtime failures.

## Limited checks and pending execution

`run-FsihZu` executes no tests: the new local closure initially omitted its
explicit error signature. Correcting that signature leaves the guard logic
unchanged. `run-hEYP4e` passes 2/2 source/control tests. `run-MWTMIi` passes
23/23 focused JS tests across the new boundary and existing UNPIVOT collision,
UNNEST and positional helper callers.

Initial Node `run-UYv5ju` is 57/59: two registration assertions still described
the old narrow object shape and old repeated-failure positions. Update them to
include the actual new executionFailures property and the independently counted
two-position shift, retaining all existing case assertions. Final `run-6VcwBH`
passes 59/59 (23 fixture, 36 inventory). Pinned formatting and
`git diff --check` pass. Final guards are terminal and release locks.

Full data-only inventory is 3,661 occurrences: 2,305 normal, 1,306 refusals,
50 execution failures; digest
`ffbb37989dedbc7de90860f54bf2765d40f5a3390bde7abd1a1debbcae309d76`.
Selected registration is 334 per transport: 200 normal, 132 refusals and two
runtime failures. Registration is not execution evidence.

At this commit normal exact clean-HEAD five-package packed Local/HTTPS
acceptance is pending. Full Core, Wasm/native, full packed corpus and CI are
unverified. No unmerged parent dependency remains; destination main. The broader
frontend goal remains incomplete.
