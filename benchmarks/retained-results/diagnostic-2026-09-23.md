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
