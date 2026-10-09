# Retained ARRAY and object star scope

## Scope and reproduced defect

The adopted main is `4ab43f593453425fe4fb43214565af227ea3bef8`. This unit carries the actual common Result schema into
CTE consumers that need correlated ARRAY or object star expansion. It changes
no language grammar, public type contract, capacity policy or execution owner.

The minimal failing query, against a declared `parents` Relation with numeric
`id` and nullable bounded numeric ARRAY `items`, is:

```aql
FROM parents |> SELECT id, items
|> UNION ALL (FROM parents |> SELECT id, items)
|> CROSS JOIN UNNEST(items) element WITH OFFSET position
|> SELECT * EXCEPT (items) |> ORDER BY id, position
```

On the adopted main, the independent ordinary append/UNNEST Program passes the
common checker and the explicit projection query also passes. The star query
fails with `UnsupportedProjection`. The focused evidence is
`_build/local-checks/attempts/run-fw8Mgd` (1/2 passed). The earlier probe at
`4551a57c9` has the same result (`run-lopygF`); it is separate evidence.

The parser already binds a set producer before a following Pipe operation.
The generated CTE consumer has a Stage Result reference, but its star schema
probe lacked that Result's actual ARRAY contract. Reusing the original input
schema would also be incorrect after projection, column aliasing or SET.

## Repair and invariants

`cte_schema_scope.mbt` asks the existing bounded member/type resolution path
for the lowered stages' Result schemas. It attaches only these schema facts
under the current CTE bindings, replacing a shadowed original schema. The outer
CTE continuation now receives this context and the existing parameter
declarations. The same connection serves later CTE bodies.

The existing common Values, Relation, append, expression and Result projection
owners decide the schemas. No row sampling, independent shape inference, key
assertion, identity, order evidence, acquisition, materialization or runtime
fallback is added. The ordinary complete Program checker still owns admission.
A refused or exhausted common probe is not retried with a larger allowance.

Public fixtures retain set duplicates and NULL elements, filter before LIMIT,
ordered output columns, current ARRAY types, nullable object receivers, empty
typed output, and rejection of dropped columns/ranges. Source-free cases require
zero Source reads. Existing acquisition, request replay and private-slot checks
are unchanged in the normal packed acceptance application.

## Verification before packing

- Selected JS MoonBit tests: 31/31, `run-8OTEoD` / `focused-test-EuCt3b`.
  Selection: `set_array_scope_test.mbt`, `cte_pipe_test.mbt`,
  `correlated_unnest_visible_star_test.mbt`, `unnest_struct_star_test.mbt`,
  `member_probe_budget_wbtest.mbt`.
- Selected Node fixture/import checks: 13/13, `run-BwucrN` /
  `focused-test-Y5VkiT`: correlated UNNEST, correlated star, joined star and
  spec-family imports.
- `node scripts/update-document-metadata.mjs --write`, then its read-only check:
  no metadata changes required. `node scripts/check-actql-spec-family.mjs`
  completed (10 documents, 1,390 requirements); this is not conformance proof.
- Changed MoonBit formatting: 4/4. `git diff --check` passed.

Two intermediate invocations are not passes: a MoonBit syntax error in the new
helper (`run-3J5muc`), and a nonexistent selected test filename (`run-CQEy2J`).
The initial extra refusal assertion named `UnknownColumn`; the existing lowerer
actually reports `Expression(UnknownReference)` for these references. The final
regression pins that precise existing category (`run-kKn278` was 24/25 before
that correction). No product refusal was weakened.

## Public acceptance status

The first normal clean-source five-package run used
`70ccbdb7dcca5549f746d0c6c353a620c23265d4`. Its manifest/digest checks and the
independent JSON control passed; the parameter-backed Pipe UNION ALL query was
rejected before admission. HTTPS was not reached. Evidence:
`_build/local-checks/attempts/run-jpqcc1` and external receipt
`worktrees/.codex-scratch/public-query-evidence-VlG2sb`.

The exact public source/declaration regression identified
`ExpressionTyping(UnknownParameter("parents"))` (`run-CrvuNs`, 5/6). Set terms
were not receiving Context's existing parameter declarations in `compile_steps`.
The repair passes those declarations and schema context without changing the
Program's parameter contract or values. A diagnostic-test compilation mistake
in `run-ajHonR` is not verification evidence.

Pending: updated normal clean-source five-package production and the existing
selected correlated-UNNEST Embedded Local / real HTTPS cohort. The new cases are also
registered in normal packed acceptance through its existing corpus connection.
A parser or checker pass alone is not public execution acceptance.

Full Core, Wasm/native execution, full packed, Cloud, performance and required
CI are not claimed. No CI was manually triggered or rerun. No PR merge is made.

## Verification after the parameter handoff repair

- Selected JS MoonBit tests: 38/38, `run-FD08KA` / `focused-test-d9rG5o`.
  This adds the exact public parameter-backed reproduction and the existing
  `parameter_reference_case_test.mbt` to the earlier selection.
- Selected Node fixture/import checks: 13/13, `run-Hz4CeW` /
  `focused-test-Maem80`. Both new public refusals pin
  `ClientProgramInvalidInput`, alongside the existing zero-admission/I/O checks.
- Two attempted extra test filenames did not exist (`run-BxXt8V`,
  `run-SWXJng`); neither invocation executed tests or establishes a pass.
- `UNION ALL` is the verified set shape in this unit; the document does not
  claim correlated ARRAY star support for every INTERSECT/EXCEPT combination.
