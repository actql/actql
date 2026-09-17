# Managed retained profile fixed-revision measurement

Date: 2026-09-17

Revision: `d14d58250dab73302aa4fadcea364a56a8265000`

Profile: `actql-managed-retained-execution/0.1`

Scope: registered 27-case matrix, one sequential diagnostic sample per case.
The worktree was clean when the runner started. Node was `v22.23.2` on Darwin
arm64. The fixed MoonBit `0.10.12+1634b282e` toolchain built the three required
JS packages before execution.

Command:

```sh
node adapters/duckdb-node/bench/managed-profile-matrix.mjs
```

All 27 cases completed. Every case reported zero logical-content CID
computations. After each case closed, held bytes and all transfer, retention and
execution reservations were zero. The elapsed time includes preparation,
execution and managed Host handling, but fixture database construction happens
before each case timer.

The abbreviations below are:

- `acquire`: native acquisition, full validation and low-selectivity output;
- `join`: fixed two-input join followed by global count;
- `reuse`: retained large output consumed by two later tasks;
- `copy`: direct DuckDB-to-Store output copies;
- `cells`: output cells materialized in JavaScript;
- `frames`: managed output frame encodes;
- `CID`: logical-content CID computations.

| workload | layout | rows | ms | copy | cells | frames | CID |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| acquire | narrow | 100 | 306.413 | 1 | 0 | 0 | 0 |
| acquire | narrow | 1,000 | 71.767 | 1 | 0 | 0 | 0 |
| acquire | narrow | 10,000 | 93.787 | 1 | 0 | 0 | 0 |
| acquire | narrow | 100,000 | 333.171 | 1 | 0 | 0 | 0 |
| acquire | narrow | 1,000,000 | 2,677.722 | 1 | 0 | 0 | 0 |
| acquire | numeric-64 | 10,000 | 1,065.003 | 1 | 0 | 0 | 0 |
| acquire | numeric-64 | 100,000 | 9,918.843 | 1 | 0 | 0 | 0 |
| acquire | text-1024 | 10,000 | 475.990 | 1 | 0 | 0 | 0 |
| acquire | text-1024 | 100,000 | 4,281.749 | 1 | 0 | 0 | 0 |
| join | narrow | 100 | 68.314 | 0 | 202 | 3 | 0 |
| join | narrow | 1,000 | 91.385 | 0 | 2,002 | 17 | 0 |
| join | narrow | 10,000 | 274.733 | 0 | 20,002 | 158 | 0 |
| join | narrow | 100,000 | 2,156.574 | 0 | 200,002 | 1,564 | 0 |
| join | narrow | 1,000,000 | 21,237.673 | 0 | 2,000,002 | 15,626 | 0 |
| join | numeric-64 | 10,000 | 1,161.800 | 0 | 20,002 | 158 | 0 |
| join | numeric-64 | 100,000 | 11,442.736 | 0 | 200,002 | 1,564 | 0 |
| join | text-1024 | 10,000 | 701.111 | 0 | 20,002 | 158 | 0 |
| join | text-1024 | 100,000 | 6,141.994 | 0 | 200,002 | 1,564 | 0 |
| reuse | narrow | 100 | 45.715 | 1 | 0 | 0 | 0 |
| reuse | narrow | 1,000 | 75.179 | 1 | 0 | 0 | 0 |
| reuse | narrow | 10,000 | 358.127 | 1 | 0 | 0 | 0 |
| reuse | narrow | 100,000 | 3,206.385 | 1 | 0 | 0 | 0 |
| reuse | narrow | 1,000,000 | 30,147.089 | 1 | 0 | 0 | 0 |
| reuse | numeric-64 | 10,000 | 8,956.490 | 1 | 0 | 0 | 0 |
| reuse | numeric-64 | 100,000 | 86,590.296 | 1 | 0 | 0 | 0 |
| reuse | text-1024 | 10,000 | 2,859.775 | 1 | 0 | 0 | 0 |
| reuse | text-1024 | 100,000 | 28,005.212 | 1 | 0 | 0 | 0 |

## Aggregate observations

| workload | cases | total ms | peak controller RSS above baseline | maximum ledger peak retention |
| --- | ---: | ---: | ---: | ---: |
| acquire | 9 | 19,224.445 | 184,205,312 bytes | 365,059,983 bytes |
| join | 9 | 43,276.320 | 115,343,360 bytes | 374,094,421 bytes |
| reuse | 9 | 160,244.268 | 210,845,696 bytes | 683,143,467 bytes |

The direct-output rule applied to all 18 acquire/reuse cases. Those cases
recorded zero JavaScript output-cell materializations and zero managed-frame
re-encodes. The join cases exercised exact two-input port order and reused the
new join result in the downstream count without a logical CID or Core
readmission. Join produces new values, so its current fallback still
materializes 2,662,218 cells and encodes 20,812 frames across the nine cases.
This is an explicit remaining physical-output optimization, not hidden work.

The earlier old-contract fixed-source diagnostic reported 22.169 seconds for
the million-row join/count, 25.216 seconds for million-row reuse, 88.049 seconds
for numeric-64/100000 reuse and 54.147 seconds for text-1024/100000 reuse. The
corresponding new-profile samples here are 21.238, 30.147, 86.590 and 28.005
seconds. These runs are from different revisions and are not alternated paired
samples, so no speed ratio or regression decision is claimed.

This measurement establishes fixed-revision functional coverage and shows
where redundant conversion, re-encoding and logical hashing are absent. It does
not replace the registered same-obligation paired performance assessment.
