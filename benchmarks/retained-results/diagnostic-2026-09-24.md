# Registered managed Host readiness diagnostic (2026-09-24)

The full registered matrix ran through the existing Node managed Host with real
DuckDB and file holdings. All 27 case IDs started and all 27 were verified;
the Node test process exited successfully after 306.5 seconds. Verification
includes independent expected logical identities, retained output, downstream
consumer use and explicit release. The raw local log is
`workspace/.codex-scratch/overall-perf-policy/registered-node-smoke-2026-09-24.log`
outside this worktree; its SHA-256 is
`cfa3f402623522fe34c58d6d2b14db2ef530cfafd81521fdffb3594e9a5f472d`.

The command was:

```sh
ACTQL_RETAINED_CASES=registered node --test \
  adapters/connectors/duckdb/node/test/benchmark-execution.test.mjs
```

This is a readiness diagnostic, not one of the registered four-comparator
paired performance measurements. Its per-case elapsed intervals include setup,
execution and cleanup and are not warm overhead or baseline ratios. The slowest
individual diagnostic case was
`retained-large-output-downstream-reuse/numeric-64/100000` at 88.8 seconds.
The test does not qualify an estimate schedule or provide native Node-free
independent holding. It does confirm that the fixed 27-case workload and its
managed file-backed product path are executable without omitting the large
capacity-infeasible baseline cases.

The separate native standard Host diagnostic still materializes intermediate
`CompletedOutput` values. It cannot be substituted for this managed path under
the registered 1 GiB ceiling by lowering a reservation estimate alone.

## Fixed-revision matched small-case diagnostic

At clean revision `c93402ffb82a0d454fdb5a2a6e0bb8744c0607fe`, the
registered `native-acquisition-full-validation-low-selectivity/narrow/100`
fixture ran in seven alternating matched pairs against the independently held
equivalent-obligations comparator. Every pair completed and passed the exact
obligation admission check. The raw pair records are in
`workspace/.codex-scratch/perf-pair-c934/seven-pairs.json` (SHA-256
`45dea636da4f9e347cf73d3f8b1fb5b35b184ec7ffdf5748eb2d88fc826cab70`).
The retained product leg still uses the example's uncalibrated estimate and is
marked `acceptanceEligible: false`; these are diagnostic pairs, not registered
acceptance samples.

| Retained minus equivalent | Minimum | Median | Maximum | Registered small-case limit |
| --- | ---: | ---: | ---: | ---: |
| Warm task interval | 28.866 ms | 31.700 ms | 33.730 ms | 10 ms |
| Fresh-process cold interval | 676.244 ms | 729.792 ms | 804.856 ms | 100 ms |

This gap cannot be closed by changing the acceptance clock or omitting Host
preparation. The current retained Node Host starts a child and prepares the
Program for each fresh Run. Its warm interval also includes three separately
admitted task executions. A product path meeting the registered boundary needs
measured placement estimates and substantially less per-Run startup and task
coordination overhead while retaining the same independent holding and guards.

The native materialized probe of the registered
`native-acquisition-full-validation-low-selectivity/numeric-64/100000` case
also failed before dispatch at this revision. Its smallest candidate declared
81,101,115,264 retained bytes against the unchanged 1 GiB ceiling. This is a
real admission rejection, not a measured allocation. Native independent
bounded holding and managed completion remain necessary before native timings
can be considered for the registered matrix.
