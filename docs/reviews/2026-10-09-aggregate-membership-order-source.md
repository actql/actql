# Aggregate membership and interval ordering: source connection

This unit starts at `1646252bdb2f47ccb683c688b258b3ff472ea1a9`
(PR #1080, Boolean aggregate ordering). It extends the same ordinary
expression admission guard. The dependency is not claimed merged or reviewed.
Final target is main; preserve the parent dependency until its integration.

## Contract and fixed counterexample

Selected primary reference: [GoogleSQL operators at d82db99a](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/operators.md).
The retained file `/private/tmp/actql-b-googlesql-operators-d82db99a.md` has
SHA-256 `70914979828c98ee5b8fb81036bc106605aa1c18560cd499febff1f1e4c626bc`.
Current [official documentation](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators)
was also inspected. BETWEEN evaluates its search value once; membership
preserves match-before-NULL and empty-set behavior; IS DISTINCT FROM has a
nonnullable Boolean result. This is not a live Google differential campaign.
The current common finite-number/type profile remains authoritative for the
selected inputs; no complete Google type-conformance claim is made.

```sql
SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (20, NULL) NULLS LAST, id)
  AS names
FROM objects
```

Before repair, an independently authored complete Program with ordinary
`derive.in` and `group.string_agg` passed the common checker. Its source
counterpart failed with `UnsupportedAggregate` (0/1, `run-lgSFim`,
`focused-test-jEvIec`). This establishes a lowering gap, not a pre-repair
published Run failure.

The total-expression guard omitted BETWEEN, IN and IS DISTINCT FROM even
though the query expression lowerer already emits their ordinary Program forms.
The common execution lowerer still rejects BETWEEN, as isolated below. Connect those
predicates and total ARRAY operand trees to that guard, then preserve ordinary
lowering. Do not expand BETWEEN into duplicate comparisons, coerce membership
NULL to FALSE, turn a computed list into literal data, or invent key evidence.
Common admission still rejects unsupported computed/annotated membership
lists. Invalid comparison domains and missing parameter declarations remain
common checking obligations. Potentially failing arithmetic/casts/LIKE remain
outside this order-key hoisting profile; masked aggregate arguments retain
existing per-call demand semantics.

## Independent expectations

Complete JSON controls and authored source use the existing public acceptance
fixture, normal corpus and `--aggregate-property-order-only` cohort. There is
no separate evaluator, Host profile, capacity override or test-side Program
repair.

- Score values 20, duplicate 10, SQL NULL object and SQL NULL member distinguish
  membership with a NULL item (`a|b|b|c`) from membership without it
  (`b|b|a|c`). Duplicates are retained.
- IN UNNEST literal lists preserve NULL atoms and repeated entries. An empty
  list is an existing total set; no ordinal substitution is performed.
- BETWEEN and NOT BETWEEN produce opposite Boolean groups. IS NOT DISTINCT
  FROM 20 yields `b|b|c|a`; IS DISTINCT FROM NULL yields `c|a|b|b`.
- SET current and original range snapshots have distinct authored expected
  strings; typed parameter values and list holes retain declarations.
- A failing aggregate argument masked by WHERE FALSE remains unexecuted.
- JSON and source ARRAY controls use explicit ASSERT UNIQUE BY, sort and
  bounded take; expect `[2,1,3,4]`, with the existing nonnullable item contract.
- Operand type, removed range, unsafe bound and DISTINCT-key refusals retain
  exact public codes and must occur before admission/provider I/O.

## Verification so far

Pinned toolchains and bounded/nonzero-test wrappers:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- --target js src/query_program/aggregate_membership_order_test.mbt src/query_program/aggregate_predicate_order_test.mbt src/query_program/in_unnest_literal_array_test.mbt src/query_program/distinct_aggregate_order_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/aggregate-conditional-order-source-input.test.mjs scripts/aggregate-signed-order-source-input.test.mjs scripts/aggregate-property-order-source-input.test.mjs
```

Pre-main-integration focused JS: 16/16 (`run-BDuJ0g`,
`focused-test-kn7s5w`). Earlier post-repair probes identified that a typed ARRAY
control is rejected by common admission; it was replaced by an unannotated
positive control and retained as a separate refusal obligation. The unsupported
INT64 test annotation was corrected to the already admitted FLOAT64 surface,
and its actual common checker refusal was fixed at that boundary. No product
contract or expected result was weakened. `run-GrsCBZ` was interrupted after an
edit script failed before writing its changes; it establishes no success.

At clean integrated source `3daf7fe1769575b13e0d3e1fc113c4917c4c2d85`, the same
focused JS selection passed 16/16 (`run-b8MzqW`, `focused-test-StKAvR`); Node
fixture checks passed 13/13 (`run-aUNh4B`, `focused-test-RlNVb9`). Main
`b40818e09295dba39de6b570b977610e95c75b1e` was normally merged, preserving
#1079's UNNEST receiver changes. #1080 remains an unmerged dependency.

## Public attempt and common-owner handoff

The normal producer packed all five packages from clean integrated source
`3daf7fe1769575b13e0d3e1fc113c4917c4c2d85`. Actual bytes were independently
checked against the manifest before the existing external acceptance consumer.

```sh
node /private/tmp/actql-b-aggregate-membership-3daf7fe17-packed-20261009.mjs
```

Producer and consumer guard: `run-amz4sY`, terminal exit 1, locks released.
Original receipt/logs: `worktrees/.codex-scratch/public-query-evidence-rDNfv0`.
The external consumer's artifacts were cleaned after evidence retention;
producer tarballs/manifest remain in
`/private/tmp/actql-b-aggregate-membership-3daf7fe17-pack`.

| Package | Actual tarball SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `3cae6b01413f4386e8d72fff427fccef96482257c966618be00b7b6886a3ecea` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

Local passed the existing 79 normal cases and the first six new membership
cases, including the independent JSON control, NULL list, Pipe, NOT IN,
IN UNNEST and empty list. The next case,
`aggregate-conditional-order-membership-between`, returned
`SubmissionUnknown` with a Host 500 `ClientHostFailure`. Its independent expected
Named Result remains `[{"names":"a|b|b|c"}]`. Later normal/refusal cases and
HTTPS were not reached. This is **partial Local evidence, not completed public
acceptance**. Run admission/provider-I/O zero was not observed for this failure.

A corrected direct-runtime diagnostic at the same built source isolates the
first failure. Both the exact authored source and the independent acquired JSON
pass ordinary preparation, then return **Err** from
`clientProgramCompileLocalTasks`, with expression kind `between`. The IN and
null-safe controls return **Ok**, resolve the installed source and issue request
identity. Evidence: `run-qKOf1E`, `focused-test-6UJ2ig`, retained compact and full
record `/private/tmp/actql-b-membership-source-preparation-probe-20261009.json`.
The test's 1/1 result means the diagnostic completed; it does not mean that all
four Programs compiled successfully. The earlier diagnostic checked only that
the compile function returned and is superseded for compilation claims.

A separate Values-only independent JSON also prepares, but task compilation
returns Err; equivalent IN and IS DISTINCT FROM controls return Ok. Evidence:
`run-tJ9NRN`, `focused-test-3Mblsy`. The simpler control's intended result is
`[{"names":"a|b|c"}]`, with nullable string column `names`.

Retained minimal inputs and reproducer:

- [Values-only independent Program](fixtures/aggregate-membership-between.program.json).
- [Independent acquired Program](fixtures/aggregate-membership-between-acquired.program.json).
- [Common task-compiler diagnostic](fixtures/aggregate-membership-between-compile.mjs).

```sh
node docs/reviews/fixtures/aggregate-membership-between-compile.mjs
```

Run against the normal prepared local-node runtime for the fixed source above;
Observed at the unchanged built source above: preparation success, Result tag 0,
expression `between`, nonzero exit (`run-Kr9Nzb`, terminal exit 1). This diagnostic is not a new execution path or a
public acceptance substitute.

The common boundary is explicit in
`src/lowering_relation/expression.mbt::expression_tag`: BETWEEN is absent and
returns `ExpressionNotImplemented("between")`. The existing
`src/lowering_relation/expression_test.mbt` case “expression budget and
unsupported handlers are explicit implementation failures” already asserts this
exact refusal. The caller chain is
`client_program_compile_local_tasks` →
`issue_prepared_client_task_compilation` → the ordinary relation expression
lowerer. The installed Host's `planFor` uses the common task compilation owner;
HTTP sanitizes the internal failure to Host 500. No public execution failure
beyond this preparation boundary has been established.

Handoff to A: implement the existing typed BETWEEN expression in the common
lowerer/evaluation frames, preserving once-only search-value evaluation, NULL
semantics, bounded work and retention. Do not replace it with two frontend
comparisons, strip the order key or weaken the expected rows. B retains the
source and independent controls and resumes the complete unchanged Local/HTTPS
cohort after an adoptable fixed SHA. No common implementation or Owner was
added in this PR.

Keep this unit Draft: all 94 planned normal cases, 40 preparation refusals and
one expected execution failure per transport must still complete; the partial
85-case Local pass does not discharge this requirement. Submitted-HEAD required
CI and content review remain unverified. Full Core, Wasm/native,
proof/performance and the entire packed campaign are not local obligations for
this focused change. This unit does not close the entire Frontend.
