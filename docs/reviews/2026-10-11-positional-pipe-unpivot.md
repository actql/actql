# UNPIVOT over positional Pipe projections

## Existing requirement and independent counterexample

The adopted Pipe UNPIVOT retains unmentioned current columns in their original
order, then emits the value column and the name column. Labels name the resolved
current input columns; private storage names are not public labels. Positional
set operands may contain anonymous or duplicate authored occurrences. Common
UNPIVOT owns expansion, exact types, NULL behavior, key transfer and capacity.

At main `ab8257c21d3dc9189499e305fc516ef4ef3af2eb`, this complete source fails
with UnsupportedProjection:

```aql
SELECT 0 AS a, 0 AS b, 'anchor' AS c
UNION ALL (
  FROM t |> SELECT x AS kept, -y
  |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept))
  |> SELECT *
)
ORDER BY a,b,c
```

For (x,y)=(1,10),(2,20), independently expected rows are
(-20,2,'kept'),(-10,1,'kept'),(0,0,'anchor'). A complete ordinary JSON control
derives neg=-y, selects kept/neg, unpivots kept while retaining neg, selects
a/b/c, appends the anchor and explicitly sorts the Named Result. It passes the
checker at the same baseline. `run-75Kl88` is 1/2: control passes and source
fails specifically with UnsupportedProjection. This is compiler evidence, not
an incorrect published Run.

Preserved test:
`/private/tmp/actql-b-positional-unpivot-ab8257c21-baseline.mbt`.
Independent Program, input and rows:
`/private/tmp/actql-b-positional-unpivot-next-candidate.json`.

## Repair and boundary

Continue positional projection discovery through Unpivot so the earlier SELECT
retains its positional role. Reserve later value/name destinations before
private-slot allocation. Validate authored selected names against current
occurrences: private anonymous values cannot be selected by their physical name,
and duplicate aliases are ambiguous. Reuse the existing UNPIVOT lowering and
common operation without changing its equality, labels, types or expansion.

The operation's fresh output scope remains intact. Old ranges and consumed
columns are not recovered, and legitimate authored names resembling private
slots remain usable. No common execution owner, contract pin, capacity
exception, fallback or consumer-side Program patch is added.

This branch starts directly from the stated main. It does not include or depend
on the still-unmerged UNNEST #1324 repair. Both units retain their separate
fixed source/package identities and public evidence.

## Independent public obligations and limited checks

Nine normal cases cover the JSON control, anonymous source, SET followed by
RENAME and current-column labels, a private-name-like destination, repeated
selected columns, retained duplicate aliases, NULL inclusion/exclusion and typed
empty output. Five preparation refusals cover a private selected name, ambiguous
alias, old range, consumed column and qualified private retained value.
The existing consumer checks Named Result rows/multiplicity, type/nullability,
column order, explicit order, hidden-column absence, Source acquisition count,
same-request Run reuse and zero admission/provider I/O for preparation refusals.

The public Source's amount is nullable. The public JSON control consequently
declares y nullable, preserving the formal Result contract even for particular
non-NULL rows. The baseline nonnullable control remains a separate historical
probe. Neither expected Program nor rows are generated from compiler output.

After repair, `run-QaCVge` passes 2/2 source/control tests. `run-i0i1p4` passes
26/26 focused JS tests for positional and ordinary UNPIVOT, projection, RENAME
and DISTINCT callers. `run-DLP7kd` passes the 20 fixture tests but its inventory
test fails because its count assertion omitted this unit's additions after
main's new Graph registrations. The data-only inventory correctly preserves
those registrations. Correcting the arithmetic leaves all row/type/order
expectations unchanged; `run-UGaXOn` passes the 36 inventory/profile tests.
Only that affected file was rerun. Pinned formatting and `git diff --check` pass.

Full registration is 3,597 occurrences: 2,265 normal, 1,284 refusals and
48 execution failures; digest
`d4f7e20be9f10a41fdbed34686057a60615b0367ed34a8e36705a89666fc99d1`.
The existing selected cohort registers 283 per transport: 170 normal and
113 refusals. Registration alone does not establish execution support.

At this commit, normal exact clean-HEAD five-package packed Local/HTTPS
execution is pending. Full Core, Wasm/native, the full packed corpus and CI
are unverified. No unmerged parent dependency; destination main. The broader
frontend goal remains incomplete.
