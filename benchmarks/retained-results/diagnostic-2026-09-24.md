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
