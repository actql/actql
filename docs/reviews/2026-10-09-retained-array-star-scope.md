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

The corrected clean-source public acceptance is recorded below. The new cases
are also registered in normal packed acceptance through its existing corpus
connection. A parser or checker pass alone is not public execution acceptance.

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

## Corrected packed Embedded Local and HTTPS acceptance

Tested source and fixture revision:
`79655310a47bb618a8887bbda6f79742208991bd`. The subsequent evidence-record
commit changes only this review document; these packages are not relabeled as
that later submitted revision.

Command (using the pinned Node and MoonBit environment):

```sh
node /private/tmp/actql-b-retained-array-79655310a-packed-20261009.mjs
```

The bounded wrapper runs normal `scripts/packed-client-packages.mjs`, verifies
all five tarballs against their manifest and actual clean HEAD, then runs
`scripts/test-packed-public-query.mjs --correlated-unnest-only` with that exact
package directory. There is no revision override, adapter overlay, patched
Program or local-only execution path. Only the job-private npm download cache
is reused. The shared heavy slot was observed occupied and allowed to finish
before this run acquired it.

- Guard: `_build/local-checks/attempts/run-ZVJdTN`; exit 0,
  complete/output complete and locks released.
- Receipt: `/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-iyd1On`.
- Every one of its 10 commands records the tested clean source revision, exit 0,
  complete output and no signal/evidence error.
- Each transport: **67 normal cases and 19 preparation refusals**; this includes
  the **9 new retained-schema positives and 2 new exact-code refusals**.
  Each normal case's name appears in its transport log. All 12 coded refusals
  have individual logs; the original 7 generic refusals use the unchanged
  complete application's rejection loop and are not claimed to have per-case
  code logs.
- Independent ordered rows and Result.describe column contracts/nullability
  match, including duplicate set rows, NULL elements, nullable object receivers,
  the changed current ARRAY type, empty typed output, filter-before-LIMIT and
  private-slot exclusion.
- Original Source acquisition/session checks and same-Run resubmit/lookup,
  attach and repeated Result reads remain passing. New source-free cases have
  no Source reads; refusals have no Run admission or Source I/O.
- README quickstart and the existing driver probes also completed. This remains
  one selected public cohort, not full packed or all-backend acceptance.

Independent receipt, command, named-case and tarball-byte audit:
`/private/tmp/actql-b-retained-array-79655310a-acceptance-audit-20261009.{mjs,json}`.
Its initial overly broad log assertion incorrectly expected a per-case line
for the original generic refusals. The existing runner only emits lines when
`expectedCode` is specified. The corrected audit preserves every coded refusal
and explicitly separates the 7 generic ones; no product test was changed.

Tarballs retained at `/private/tmp/actql-b-retained-array-79655310a-pack`:

| Package | SHA-256 |
|---|---|
| `client-wire` | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| `sdk` | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| `run-host-core` | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| `local-node` | `dd4f876444fd90ef9500970611a9b9abdaedb97058bd046aef10813458c97052` |
| `node` | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

## Cleanup and remaining verification

Both own packed handles were terminal before removing only
`/private/tmp/actql-b-retained-array-70ccbdb7d-pack/npm-cache/_cacache`.
It held 46,350,336 allocated bytes (about 44.2 MiB). Its ownership, no-symlink /
no-shared-hardlink tree and no-open-file checks passed. Logs, both package sets,
manifests, failure/success receipts, source and borrowed dependencies remain.
Cleanup receipt: `/private/tmp/actql-b-retained-array-cache-cleanup-20261009.json`.
The standard public runner also removed its own finished installation roots
while retaining evidence.

This unit's implementation and selected public execution are complete. Required
CI and review remain separate; full Core, Wasm/native execution, all set forms,
Cloud and performance are unverified here. No merge or manual CI rerun is made.
