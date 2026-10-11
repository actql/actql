# DISTINCT over positional Pipe input

## Existing requirement and fixed counterexamples

Pipe DISTINCT compares the complete current visible row, preserving evaluated
column occurrences, types, NULL equality and surviving range bindings. Anonymous
and duplicate authored columns remain valid positional set operands. These are
existing requirements in `docs/spec/query-text.md`, not a new equality profile.

Baseline `c11bd3afe887eba29d38bd539217a86cebb01ccd` normally merges main
`c2267b2734acff76894a332db445d120dfc7b4af`, including the prior ORDER-window
repair. This complete source fails with UnsupportedProjection:

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -y |> DISTINCT
)
ORDER BY a, b
```

Changing the inner projection to `x AS v, -y AS \`V\`` instead fails with
DuplicateOutput. With input (1,10),(1,20),(1,10), the independent expected
rows are (0,0),(1,-20),(1,-10). Comparing only the named kept column would
incorrectly collapse the two distinct anonymous values.

An independently authored complete JSON Program derives neg=-y, projects
kept/neg, applies `distinct: ["kept", "neg"]`, selects a/b, appends the anchor
and explicitly sorts the Named Result. Baseline guard `run-7QtzAI` executes
three tests: the JSON control passes, both source forms fail with their concrete
diagnostics. This proves a compiler/checker gap, not an incorrect published Run.
Preserved baseline test:
`/private/tmp/actql-b-positional-distinct-c11bd3afe-baseline.mbt`.
Independent Program, source, input and expected rows:
`/private/tmp/actql-b-positional-distinct-independent-control.json`.

## Minimal repair and independent obligations

Continue `positional_set_terminal_projection` through standalone Distinct.
Reuse the existing compiler's complete visible-slot keys, private-value pruning
and range pruning. No equality, checker, runtime owner, capacity limit, wire,
pin, fallback or consumer-side Program correction changes.

Nine normal public cases cover the complete JSON control, anonymous projection,
duplicate aliases, a surviving immutable range, SET-displaced values excluded
from equality keys, DROP after DISTINCT, nullable values, typed empty output,
and declared parameters with explicit ORDER/LIMIT/OFFSET. For the DROP case,
two different complete rows become the same anonymous value afterward: both
must remain. Neither moving DROP before DISTINCT nor applying another DISTINCT
after DROP preserves the required multiplicity.

Six preparation refusals cover private anonymous names, ambiguous aliases,
dropped input, displaced ranges, SET-pruned range values and qualified private
names. MoonBit assertions retain concrete UnknownColumn, AmbiguousColumn and
Expression/UnknownReference diagnostics. Public assertions retain the typed
ClientProgramInvalidInput code and zero Run admission/provider I/O.

The public Source contract declares amount nullable. The public JSON control
therefore independently declares y nullable, and expects b nullable even when
the particular rows contain no NULL. The nonnullable baseline control remains
a separate historical compiler probe. Types are not sampled from rows.

The existing consumer checks Named Result rows, multiplicity, explicit order,
Result.describe types/nullability/column order, hidden-column absence, Source
acquisition count and same-request Run reuse. Expected Programs and rows are
authored independently; execution does not patch the compiler's output.

## Validation and remaining evidence

After repair, `run-FzENtX` passes the three baseline/control tests.
`run-I3F1Z6` passes 25/25 focused JS tests across positional DISTINCT, ordinary
and JOIN Pipe DISTINCT, positional projection, DROP and ORDER-window callers.
`run-qmceSa` passes 55/55 targeted Node tests (19 fixture, 36 inventory).
Both final guards are complete, exit zero and release their locks. Pinned
MoonBit formatting and `git diff --check` pass.

The data-only public inventory has 3,552 occurrences: 2,239 normal, 1,266
refusals and 47 execution failures, digest
`288a9fc8f9cc82e638eab6d58d89d4a2826f70b1d5b7e7b26d2f50dedf4ae720`.
The existing selected cohort registers 269 cases per transport: 161 normal,
108 refusals. Registration is not execution evidence.

At this commit, normal exact clean-HEAD five-package packed Local/HTTPS
acceptance is pending. Full Core, Wasm/native, the full packed corpus and CI
are not claimed. No unmerged parent dependency remains; final destination is
main. This closes one composition boundary only. The broader frontend goal
remains incomplete.
