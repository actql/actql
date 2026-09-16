# Capacity-infeasible baseline comparisons: approved addendum

Approved by the user on 2026-09-16, before formal measurement under this policy.
This supplements, and does not overwrite, `experiment.json` (SHA-256
`83fc5ce32f20de2492ef862726e057a03b43d46e0488023742550a25b4fff305`).
The registered fixtures, 27 cases, timeouts, timing thresholds, alternating
pairs and confidence requirements are unchanged. Retention remains 1 GiB
(1,073,741,824 bytes); raising it is outside this experiment.

## Reason and exact exception

The pinned baseline's declared retention requirements exceed the ceiling in
nine cases. Requiring successful timing ratios for those cases is impossible
without changing the resource conditions. `baseline-feasibility.mjs` records
the pinned source evidence and conservative required-capacity lower bounds.
These are lower bounds, not exact allocations, measured RSS or measured
runtime rejection events. Runtime refusal evidence, when obtained, is recorded
separately. Neither kind of evidence supplies a successful timing sample.

Only a baseline case with verified capacity evidence exceeding the unchanged
ceiling may receive `ratio-not-computable`. Record its reason, required-capacity
lower bound and applied limit. If the new implementation completes, report
"baseline infeasible within capacity; retained implementation feasible".
Never report infinite speedup. For all other baseline cases, successful paired
samples remain necessary; `not-ruled-out` does not mean executable.

## Unchanged mandatory acceptance

- The retained implementation must complete every registered case with the
  same semantics, obligations and resources. Its timeout, capacity refusal or
  unsupported profile cannot become an exclusion or a pass.
- Complete the direct DuckDB comparator with identical validation, identities,
  intermediate obligations, independent holding and resource conditions.
  Attempt every case. Comparator failures require investigation and leave the
  comparison undetermined; they never grant automatic acceptance.
- All 27 equivalent-obligation comparisons must be established and meet the
  original timing gates before reporting performance acceptance. The large
  ratio remains 1.25; small warm/cold overhead limits remain 10/100 ms.
- Semantic, ownership, cleanup and structural checks remain mandatory.
  A timing result alone cannot certify those checks or comparator equivalence.

## Evidence separation

Historical probes and observations remain diagnostics. Do not retroactively
label them formal samples. Formal samples must identify this addendum, fixed
implementation revision, toolchain, configurations, resource ceilings and
timing boundaries. Preserve failed/unfinished cases in the report. The nine
baseline exceptions change comparison eligibility, not the performance target.
