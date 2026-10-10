# Positional exports through postprojection Pipe WHERE

## Preserved counterexample

```aql
SELECT 0 AS a
UNION ALL (FROM t |> SELECT -x |> WHERE FALSE)
ORDER BY a
```

For independent input `x = 1, 2`, only the left zero survives. Expected rows
are `[{"a":0}]`. Moving the predicate after append would incorrectly remove
that zero; dropping it would publish two extra rows. SQL NULL as the right
Boolean predicate also selects no right rows under the common filter contract.

At parent `5a7227a6766dc7bd1a61dc6203fc59cb4ccb8a08`, the preserved two-case
probe reported `UnsupportedProjection` for text while the independently
authored ordinary JSON control passed the common checker: 1/2. Guard
`run-rGF1eE`, focused evidence `focused-test-TDKzAG`, in the parent's worktree.
The exact test and SHA-256 record are retained as
`/private/tmp/actql-b-positional-filter-audit-5a7227a67.mbt` and `.json`.
This establishes a lowering refusal, not an executing Run's wrong result.

## Minimal frontend connection

The final positional SELECT retains its output role through ordinary trailing
WHERE as well as ORDER/LIMIT. WHERE changes rows without adding column names.
After SELECT materializes, reference checking uses the existing current Pipe
scope. Retained authored aliases are visible; removed input fields, old ranges,
private physical fields and ambiguous duplicate aliases are not made visible.
The ORDER guard continues to use the existing SELECT-owned input snapshot.

Only the positional helper and its private-reference check in `compile_steps`
change. Existing WHERE expression lowering, D's CTE/predicate/assert/Effect
functions, and all common checker/planner/runtime owners remain unchanged.
Anonymous public outputs and BY NAME exports are not granted by this change.
No execution limit, type contract, canonical value, pin or wire changes.

## Independent fixtures and actual local verification

The ordinary JSON control derives `neg`, projects to `a`, filters FALSE before
append, appends the left zero and sorts `a`. Expected Program values and result
rows are independently authored; no source output is patched in the harness.

Five focused tests cover that control, retained named aliases, analytic and
duplicate ordinal values, NULL predicates, exact missing-reference diagnostics,
private generated receivers and duplicate-alias ambiguity. The generated private
field suffix is checked against a real accepted Program before testing refusal.

Seven new normal cases and four exact invalid-input refusals join the existing
ordinary/narrow public consumer. It will check actual Result.describe types and
nullability, declaration order, rows, private-column absence, shared Source
acquisition, same-request reuse and refusal before admission/provider I/O.
The inherited and new selected corpus totals 106 cases per Local/HTTPS transport;
this is registration, not a claim of execution.

After repair, the two-case probe passed 2/2 (`run-BRSCcI`) and the expanded
file passed 5/5 (`run-lniHb1`). Selected changed/caller verification
`run-D2KzhP` passed 27/27 JS tests and 45/45 Node fixture/inventory tests.
No full Core, Wasm/native execution, proof, performance or public packed campaign
was run for this unit. These are pending-patch local results, not CI evidence.

Authored inventory: 3,389 occurrences, 2,148 normal, 1,194 refusal and 47
execution-failure cases. Digest:
`46e8dac9b13b2b1e8f34d3ebb23e82938053bae6a9a767664abf009d2f313094`.
This inventory identifies independent authored obligations; it generates no
expected rows or types.

## Dependency and next acceptance

This isolated branch depends on unmerged #1283. Preserve that base until its
parent reaches main; the final destination is main. The parent's exact HEAD and
95-case public acceptance remain separate from this child's evidence. Retain
both original counterexamples and do not use child packages as parent-SHA proof.

Use normal clean-SHA five-package production and the existing
`test-packed-public-query.mjs --set-corresponding-only` consumer after the shared
heavy slot becomes available. Record the child revision, package digests and
terminal Local/HTTPS receipts in its PR body. Public execution, hosted CI and
broader frontend completion remain unverified until their own evidence exists.

The isolated worktree borrows the protected dependency directory
`/Users/t14i/workspace/20260822/worktrees/actql-frontend-qualify-group-aggregate-slots/node_modules`.
Its `_build` and test evidence are separate; no other-owner or shared output was
deleted, modified or reused as current-source execution proof.
