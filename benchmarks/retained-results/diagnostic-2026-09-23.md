# Retained performance diagnostic, 2026-09-23

This is a diagnostic failure observation, not the 27-case acceptance result.
The product leg used revision
`e4029354d452732d6c205fd6132ca54d74019248`, Node `v22.23.2`, the
registered `native-acquisition-full-validation-low-selectivity/narrow/100`
fixture, and an immutable source database with SHA-256
`59f54db95d569402ab61a4a960892b3aeabac91e103bada49f1e4d6088c90871`.
Seven fresh-process pairs alternated the retained ActQL leg and the direct
DuckDB leg with identical obligations and independent holding. The paired
runner admitted their logical and resource accounting equivalence. The
retained leg selected with the explicit example estimate
`nativeMilliseconds: "1"`; it did **not** use a calibrated ordinary cost
model. Only one of the 27 cases was measured, so no formal performance gate
has passed.

| Duration, ms | Minimum | Median | Maximum |
| --- | ---: | ---: | ---: |
| Retained ActQL execution cycle | 1492 | 1650 | 1791 |
| Equivalent direct execution cycle | 71 | 88 | 165 |
| Paired warm overhead | 5 | 13 | 28 |
| Paired cold overhead | 1521 | 1693 | 1799 |
| ActQL parent preparation | 460 | 516 | 555 |
| ActQL child process start | 180 | 195 | 228 |
| ActQL child preparation | 459 | 502 | 556 |
| ActQL child execution | 314 | 404 | 449 |

The preregistered small-case limits are 10 ms warm and 100 ms cold overhead.
The median diagnostic exceeds both, especially the cold limit. Parent and
child each import and prepare the application; the child boundary also incurs
process startup. A separate CPU profile of this case attributed roughly 175 ms
under Program checking within application preparation. Hashing did not dominate
that small-case profile. These nested timings are observations, not additive
exclusive CPU costs. `NODE_COMPILE_CACHE` reduced a separate warm-cache run to
about 1.14 s, still far above the cold limit.

Next acceptance work must use a normal cost-grounded placement decision, run
all 27 cases under the registered 1 GiB ceiling, and perform the registered
paired statistical assessment. The current example's fixed local and native
cost rates cannot serve as measured calibration. Any optimization must retain
the same checked task boundaries, validation, identity obligations, holding,
and cleanup. A smaller timer boundary or a forced native choice would not close
this result.

## Later fixed-revision paired diagnostic

At clean revision `3f3b61e2c86bc40900e1386f79bfb0abf13c2c3b`, the same
fixture and source hash were run in seven new alternating fresh-process pairs.
Each pair passed the independent obligation admission. This revision uses a
common Host task clock for its warm interval, so these numbers should not be
pooled with the earlier table. Median product and direct execution cycles were
699 ms and 34 ms. Median parent preparation, worker preparation and child
start were 218 ms, 217 ms and 81 ms respectively.

Applying the preregistered 10,000-resample, 95% paired timing helper to this
one case produced:

| Difference | Estimate | 95% interval | Registered limit | Result |
| --- | ---: | ---: | ---: | --- |
| Warm task interval | 29.0 ms | 27.3–30.6 ms | 10 ms | Fail |
| Cold process interval | 712.1 ms | 694.3–722.7 ms | 100 ms | Fail |

The pair runner still used the explicit example estimate rather than a
measured, versioned placement profile, and this remains a single-case
diagnostic. It is sufficient to identify a current blocker; it is not a
complete formal experiment. The parent and child each perform application
preparation, including a full Program check, before the retained completion.
Removing that duplicate work or choosing a different normal execution profile
must preserve independent validation, authority, holding and cleanup.

A temporary whitebox timing probe used the existing checked three-task Program
fixture, without native DuckDB I/O. Its three preparation calls took 7.7–8.2 ms
on the native target and 6.6–8.3 ms on JS after the surrounding test suite had
already warmed the module. The probe was removed after measurement. This is not
an equivalent benchmark leg and cannot be substituted for the registered
Program or its cold-start cost. It does suggest that a native end-to-end
execution profile is worth measuring before changing semantic validation or
weakening the timing boundary.

## Native preparation probe

The existing release-built `native_remote_application_inspect` executable loaded
the registered narrow 100-row Program, Environment, parameters and contracts
through `load_native_remote_application`. Ten fresh native processes each
reported the same four-task checked graph and completed in 10.6–12.6 ms from
parent spawn to child exit (median 10.9 ms) on macOS arm64. The input files were
generated from `managedCaseConfiguration`; the loader used its current default
data profile rather than the JS benchmark's explicit `DataProfile`. The probe
did not open DuckDB, execute tasks, retain output, or verify cleanup. It is not
an equivalent comparator or an acceptance sample. It does establish that native
Program preparation and process startup are much smaller than the measured
JS parent/child preparation cost for this fixture. The next product diagnostic
should execute the same checked fixture through the native Host with its exact
data profile and independent holding before selecting an optimization target.
